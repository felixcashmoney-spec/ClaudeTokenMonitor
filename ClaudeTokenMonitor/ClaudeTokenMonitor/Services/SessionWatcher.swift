import Foundation
import SwiftData
import Combine

@MainActor
final class SessionWatcher: ObservableObject {
    @Published var isWatching = false

    private var modelContext: ModelContext?
    private var fileOffsets: [URL: UInt64] = [:]
    private var timer: Timer?
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var directoryHandle: CInt = -1

    private var claudeProjectsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    func start(modelContext: ModelContext) {
        self.modelContext = modelContext
        isWatching = true

        // Initial scan of all existing session files
        performFullScan()

        // Poll every 5 seconds for new data
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollForChanges()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isWatching = false
    }

    private func performFullScan() {
        let projectDirs = findProjectDirectories()
        for (projectPath, jsonlFiles) in projectDirs {
            for file in jsonlFiles {
                processSessionFile(file, projectPath: projectPath, isInitialScan: true)
            }
        }
        try? modelContext?.save()
    }

    private func pollForChanges() {
        let projectDirs = findProjectDirectories()
        var hasChanges = false

        for (projectPath, jsonlFiles) in projectDirs {
            for file in jsonlFiles {
                let offset = fileOffsets[file] ?? 0
                let (records, newOffset) = JSONLParser.parseNewLines(in: file, afterByteOffset: offset)

                if !records.isEmpty {
                    let sessionId = file.deletingPathExtension().lastPathComponent
                    let session = findOrCreateSession(
                        sessionId: sessionId,
                        projectPath: projectPath,
                        model: records.first?.model ?? "unknown",
                        createdAt: records.first?.timestamp ?? Date()
                    )

                    for record in records {
                        let tokenRecord = TokenRecord(
                            timestamp: record.timestamp,
                            inputTokens: record.inputTokens,
                            outputTokens: record.outputTokens,
                            cacheCreationInputTokens: record.cacheCreationInputTokens,
                            cacheReadInputTokens: record.cacheReadInputTokens,
                            isRateLimited: record.isRateLimited
                        )
                        tokenRecord.session = session
                        session.tokenRecords.append(tokenRecord)
                        session.lastActivityAt = record.timestamp
                        if record.model != "unknown" {
                            session.model = record.model
                        }
                        modelContext?.insert(tokenRecord)
                    }
                    hasChanges = true
                }
                fileOffsets[file] = newOffset
            }
        }

        if hasChanges {
            try? modelContext?.save()
        }
    }

    private func processSessionFile(_ url: URL, projectPath: String, isInitialScan: Bool) {
        let (sessionId, records) = JSONLParser.parseSessionFile(at: url)
        guard !records.isEmpty else {
            fileOffsets[url] = 0
            return
        }

        let session = findOrCreateSession(
            sessionId: sessionId,
            projectPath: projectPath,
            model: records.first?.model ?? "unknown",
            createdAt: records.first?.timestamp ?? Date()
        )

        // Only add records if this is initial scan and session has no records yet
        if isInitialScan && session.tokenRecords.isEmpty {
            for record in records {
                let tokenRecord = TokenRecord(
                    timestamp: record.timestamp,
                    inputTokens: record.inputTokens,
                    outputTokens: record.outputTokens,
                    cacheCreationInputTokens: record.cacheCreationInputTokens,
                    cacheReadInputTokens: record.cacheReadInputTokens,
                    isRateLimited: record.isRateLimited
                )
                tokenRecord.session = session
                session.tokenRecords.append(tokenRecord)
                modelContext?.insert(tokenRecord)
            }
            if let lastRecord = records.last {
                session.lastActivityAt = lastRecord.timestamp
            }
        }

        // Track file offset for incremental updates
        if let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64 {
            fileOffsets[url] = fileSize
        }
    }

    private func findOrCreateSession(sessionId: String, projectPath: String, model: String, createdAt: Date) -> Session {
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.sessionId == sessionId }
        )
        if let existing = try? modelContext?.fetch(descriptor).first {
            return existing
        }

        let session = Session(sessionId: sessionId, projectPath: projectPath, model: model, createdAt: createdAt)
        modelContext?.insert(session)
        return session
    }

    private func findProjectDirectories() -> [(String, [URL])] {
        let fm = FileManager.default
        let projectsDir = claudeProjectsURL
        guard let projectDirs = try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil) else {
            return []
        }

        var results: [(String, [URL])] = []
        for dir in projectDirs where dir.hasDirectoryPath {
            // Decode project path from directory name (dashes replace slashes)
            let dirName = dir.lastPathComponent
            let projectPath = dirName.replacingOccurrences(of: "-", with: "/")

            let jsonlFiles = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
                .filter { $0.pathExtension == "jsonl" } ?? []

            if !jsonlFiles.isEmpty {
                results.append((projectPath, jsonlFiles))
            }
        }
        return results
    }
}
