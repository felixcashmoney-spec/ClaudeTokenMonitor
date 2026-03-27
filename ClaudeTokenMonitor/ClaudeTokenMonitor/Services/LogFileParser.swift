import Foundation
import Combine

// MARK: - Model Structs

struct WindowInfo {
    let status: String          // "exceeded_limit" or "within_limit"
    let resetsAt: Date          // from Unix timestamp
    let utilization: Double     // 0.0 to 1.0+
    let surpassedThreshold: Double?
}

struct RateLimitInfo {
    let timestamp: Date         // when the log entry was written
    let type: String            // "exceeded_limit"
    let resetsAt: Date          // top-level resets_at
    let fiveHourWindow: WindowInfo
    let sevenDayWindow: WindowInfo
    let overageStatus: String?
    let overageDisabledReason: String?  // "out_of_credits", "org_level_disabled", nil
    let overageInUse: Bool
}

// MARK: - LogFileParser

@MainActor
final class LogFileParser: ObservableObject {
    @Published var latestInfo: RateLimitInfo?

    private let logFileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Claude/claude.ai-web.log")
    }()

    private var timer: Timer?
    private var fileByteOffset: UInt64 = 0

    private static let logTimestampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current  // Log timestamps are in local time
        return df
    }()

    func start() {
        // Initial full parse to find the most recent entry
        parseLogFile(fullScan: true)

        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.parseLogFile(fullScan: false)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func parseLogFile(fullScan: Bool) {
        guard FileManager.default.fileExists(atPath: logFileURL.path) else {
            return
        }

        guard let fileHandle = try? FileHandle(forReadingFrom: logFileURL) else {
            return
        }
        defer { try? fileHandle.close() }

        let readOffset: UInt64
        if fullScan {
            readOffset = 0
        } else {
            readOffset = fileByteOffset
        }

        // Seek to the offset
        do {
            try fileHandle.seek(toOffset: readOffset)
        } catch {
            return
        }

        let data = fileHandle.readDataToEndOfFile()
        guard !data.isEmpty else { return }

        // Update file offset for next incremental read
        let newOffset = readOffset + UInt64(data.count)
        fileByteOffset = newOffset

        guard let content = String(data: data, encoding: .utf8) else { return }

        // Process lines looking for COMPLETION failed entries with exceeded_limit JSON
        let lines = content.components(separatedBy: "\n")
        var latestFound: RateLimitInfo? = nil

        for line in lines {
            guard line.contains("[COMPLETION] Request failed Error:") else { continue }

            if let info = parseRateLimitLine(line) {
                // Keep the most recent
                if let existing = latestFound {
                    if info.timestamp > existing.timestamp {
                        latestFound = info
                    }
                } else {
                    latestFound = info
                }
            }
        }

        if let found = latestFound {
            // Only update if this entry is newer than what we have (or we have nothing)
            if let current = latestInfo {
                if found.timestamp > current.timestamp {
                    latestInfo = found
                }
            } else {
                latestInfo = found
            }
        }
    }

    private func parseRateLimitLine(_ line: String) -> RateLimitInfo? {
        // Format: 2026-03-27 01:12:11 [error] [COMPLETION] Request failed Error: {...json...}
        // Extract timestamp from beginning: "2026-03-27 01:12:11"
        let entryTimestamp: Date
        if line.count >= 19 {
            let timestampStr = String(line.prefix(19))
            entryTimestamp = Self.logTimestampFormatter.date(from: timestampStr) ?? Date()
        } else {
            entryTimestamp = Date()
        }

        // Find "Error: " and extract the JSON after it
        guard let errorRange = line.range(of: "Error: ") else { return nil }
        let jsonString = String(line[errorRange.upperBound...]).trimmingCharacters(in: .whitespaces)

        guard let jsonData = jsonString.data(using: .utf8),
              let jsonObj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        // Check type
        guard let type = jsonObj["type"] as? String, type == "exceeded_limit" else { return nil }

        // Top-level resets_at
        guard let resetsAtRaw = jsonObj["resetsAt"] as? Double else { return nil }
        let resetsAt = Date(timeIntervalSince1970: resetsAtRaw)

        // Extract windows
        guard let windows = jsonObj["windows"] as? [String: Any] else { return nil }
        guard let fiveHourRaw = windows["5h"] as? [String: Any],
              let sevenDayRaw = windows["7d"] as? [String: Any] else { return nil }

        guard let fiveHour = parseWindowInfo(fiveHourRaw),
              let sevenDay = parseWindowInfo(sevenDayRaw) else { return nil }

        // Extra usage fields
        let overageStatus = jsonObj["overageStatus"] as? String
        let overageDisabledReason = jsonObj["overageDisabledReason"] as? String
        let overageInUse = jsonObj["overageInUse"] as? Bool ?? false

        return RateLimitInfo(
            timestamp: entryTimestamp,
            type: type,
            resetsAt: resetsAt,
            fiveHourWindow: fiveHour,
            sevenDayWindow: sevenDay,
            overageStatus: overageStatus,
            overageDisabledReason: overageDisabledReason,
            overageInUse: overageInUse
        )
    }

    private func parseWindowInfo(_ dict: [String: Any]) -> WindowInfo? {
        guard let status = dict["status"] as? String,
              let resetsAtRaw = dict["resets_at"] as? Double,
              let utilization = dict["utilization"] as? Double else {
            return nil
        }

        let surpassedThreshold = dict["surpassed_threshold"] as? Double

        return WindowInfo(
            status: status,
            resetsAt: Date(timeIntervalSince1970: resetsAtRaw),
            utilization: utilization,
            surpassedThreshold: surpassedThreshold
        )
    }
}
