import Foundation
import SwiftData
import Combine

@MainActor
final class SessionWatcher: ObservableObject {
    @Published var isWatching = false
    @Published var lastRateLimitMessage: String?

    private var modelContext: ModelContext?
    private var fileOffsets: [URL: UInt64] = [:]
    private var timer: Timer?

    private var claudeProjectsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    func start(modelContext: ModelContext) {
        self.modelContext = modelContext
        isWatching = true

        performFullScan()

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
        let allFiles = findAllJSONLFiles()
        for file in allFiles {
            processSessionFile(file, isInitialScan: true)
        }
        try? modelContext?.save()
    }

    private func pollForChanges() {
        let allFiles = findAllJSONLFiles()
        var hasChanges = false

        for file in allFiles {
            let offset = fileOffsets[file] ?? 0
            let (records, newOffset) = JSONLParser.parseNewLines(in: file, afterByteOffset: offset)

            if !records.isEmpty {
                // Use cwd from the first record that has it, or derive from directory
                let projectPath = records.first(where: { $0.cwd != nil })?.cwd
                    ?? deriveProjectPath(from: file)

                // Session ID: use the main session file name (not subagent)
                let sessionId = extractSessionId(from: file)

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

                    if record.model != "unknown" && record.model != "<synthetic>" {
                        session.model = record.model
                    }
                    if let cwd = record.cwd {
                        session.projectPath = cwd
                        session.projectName = Session.extractProjectName(from: cwd)
                    }
                    if record.isRateLimited, let msg = record.rateLimitResetMessage {
                        session.lastRateLimitMessage = msg
                        lastRateLimitMessage = msg
                    }
                    modelContext?.insert(tokenRecord)
                }
                hasChanges = true
            }
            fileOffsets[file] = newOffset
        }

        if hasChanges {
            try? modelContext?.save()
        }
    }

    private func processSessionFile(_ url: URL, isInitialScan: Bool) {
        let (_, records) = JSONLParser.parseSessionFile(at: url)
        guard !records.isEmpty else {
            fileOffsets[url] = 0
            return
        }

        let projectPath = records.first(where: { $0.cwd != nil })?.cwd
            ?? deriveProjectPath(from: url)
        let sessionId = extractSessionId(from: url)

        let session = findOrCreateSession(
            sessionId: sessionId,
            projectPath: projectPath,
            model: records.first?.model ?? "unknown",
            createdAt: records.first?.timestamp ?? Date()
        )

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

                if let cwd = record.cwd {
                    session.projectPath = cwd
                    session.projectName = Session.extractProjectName(from: cwd)
                }
                if record.isRateLimited, let msg = record.rateLimitResetMessage {
                    session.lastRateLimitMessage = msg
                    lastRateLimitMessage = msg
                }
            }
            if let lastRecord = records.last {
                session.lastActivityAt = lastRecord.timestamp
            }
        }

        if let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64 {
            fileOffsets[url] = fileSize
        }
    }

    /// Extract the main session ID from any file path (including subagent paths)
    private func extractSessionId(from url: URL) -> String {
        // Subagent path: .../SESSION_UUID/subagents/agent-HASH.jsonl
        // Main path: .../SESSION_UUID.jsonl
        let components = url.pathComponents
        if let subagentIdx = components.firstIndex(of: "subagents"),
           subagentIdx > 0 {
            // Parent of "subagents" is the session UUID directory
            return components[subagentIdx - 1]
        }
        return url.deletingPathExtension().lastPathComponent
    }

    /// Derive project path from the directory name (fallback when cwd not in JSONL)
    private func deriveProjectPath(from url: URL) -> String {
        // Walk up to find the project directory under ~/.claude/projects/
        var current = url.deletingLastPathComponent()
        let projectsPath = claudeProjectsURL.path

        while current.path != projectsPath && current.path != "/" {
            let parent = current.deletingLastPathComponent()
            if parent.path == projectsPath {
                // current is the project directory
                // Directory name like "-Users-felixleis-ClaudeCode"
                // First char is always "-" (leading slash), rest are path components
                let dirName = current.lastPathComponent
                if dirName.hasPrefix("-") {
                    return dirName.replacingOccurrences(of: "-", with: "/")
                }
                return dirName
            }
            current = parent
        }
        return "Unknown"
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

    /// Find all JSONL files including subagent files
    private func findAllJSONLFiles() -> [URL] {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(at: claudeProjectsURL, includingPropertiesForKeys: nil) else {
            return []
        }

        var allFiles: [URL] = []
        for dir in projectDirs where dir.hasDirectoryPath {
            allFiles.append(contentsOf: findJSONLRecursive(in: dir))
        }
        return allFiles
    }

    private func findJSONLRecursive(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }

        var files: [URL] = []
        for item in contents {
            if item.pathExtension == "jsonl" {
                files.append(item)
            } else if item.hasDirectoryPath {
                // Recurse into subdirectories (session dirs with subagents)
                files.append(contentsOf: findJSONLRecursive(in: item))
            }
        }
        return files
    }
}
