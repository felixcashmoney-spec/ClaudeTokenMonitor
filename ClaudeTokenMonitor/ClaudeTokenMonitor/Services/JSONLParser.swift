import Foundation

struct ParsedTokenUsage {
    let timestamp: Date
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationInputTokens: Int
    let cacheReadInputTokens: Int
    let model: String
    let isRateLimited: Bool
    let rateLimitResetMessage: String?
    let cwd: String?
}

struct JSONLParser {
    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parseSessionFile(at url: URL) -> (sessionId: String, records: [ParsedTokenUsage]) {
        let sessionId = url.deletingPathExtension().lastPathComponent
        guard let data = try? String(contentsOf: url, encoding: .utf8) else {
            return (sessionId, [])
        }

        var records: [ParsedTokenUsage] = []
        for line in data.components(separatedBy: .newlines) where !line.isEmpty {
            if let record = parseLine(line) {
                records.append(record)
            }
        }
        return (sessionId, records)
    }

    static func parseNewLines(in url: URL, afterByteOffset offset: UInt64) -> (records: [ParsedTokenUsage], newOffset: UInt64) {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return ([], offset)
        }
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()
        guard fileSize > offset else {
            return ([], offset)
        }

        handle.seek(toFileOffset: offset)
        let newData = handle.readDataToEndOfFile()
        let newOffset = handle.offsetInFile

        guard let text = String(data: newData, encoding: .utf8) else {
            return ([], newOffset)
        }

        var records: [ParsedTokenUsage] = []
        for line in text.components(separatedBy: .newlines) where !line.isEmpty {
            if let record = parseLine(line) {
                records.append(record)
            }
        }
        return (records, newOffset)
    }

    private static func parseLine(_ line: String) -> ParsedTokenUsage? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        guard let type = json["type"] as? String, type == "assistant" else {
            return nil
        }

        guard let message = json["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else {
            return nil
        }

        let timestampStr = json["timestamp"] as? String ?? ""
        let timestamp = iso8601.date(from: timestampStr) ?? Date()
        let model = message["model"] as? String ?? "unknown"
        let cwd = json["cwd"] as? String

        let inputTokens = usage["input_tokens"] as? Int ?? 0
        let outputTokens = usage["output_tokens"] as? Int ?? 0
        let cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0

        // Detect rate limiting via error field or content text
        let errorField = json["error"] as? String
        let isRateLimited = errorField == "rate_limit"

        // Extract rate limit reset message from content
        var rateLimitResetMessage: String?
        if isRateLimited, let content = message["content"] as? [[String: Any]] {
            for block in content {
                if let text = block["text"] as? String, text.contains("resets") {
                    rateLimitResetMessage = text
                    break
                }
            }
        }

        return ParsedTokenUsage(
            timestamp: timestamp,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationInputTokens: cacheCreation,
            cacheReadInputTokens: cacheRead,
            model: model,
            isRateLimited: isRateLimited,
            rateLimitResetMessage: rateLimitResetMessage,
            cwd: cwd
        )
    }
}
