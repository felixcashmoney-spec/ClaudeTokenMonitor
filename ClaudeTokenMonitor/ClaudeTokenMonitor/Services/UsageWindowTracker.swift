import Foundation
import SwiftData

struct UsageWindow {
    let tokensUsed: Int
    let learnedLimit: Int?
    let resetTime: Date?
    let windowStart: Date
    let isLimited: Bool

    var remaining: Int? {
        guard let limit = learnedLimit else { return nil }
        return max(0, limit - tokensUsed)
    }

    var usagePercent: Double? {
        guard let limit = learnedLimit, limit > 0 else { return nil }
        return Double(tokensUsed) / Double(limit)
    }
}

@MainActor
final class UsageWindowTracker: ObservableObject {
    @Published var currentWindow: UsageWindow?

    private var modelContext: ModelContext?
    private var timer: Timer?

    /// Claude Pro resets usage in ~5 hour windows
    private let windowDuration: TimeInterval = 5 * 60 * 60

    func start(modelContext: ModelContext) {
        self.modelContext = modelContext
        evaluate()

        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluate()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func evaluate() {
        guard let modelContext else { return }

        // Find the most recent rate limit event to determine window boundaries
        let allRecordsDescriptor = FetchDescriptor<TokenRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let allRecords = (try? modelContext.fetch(allRecordsDescriptor)) ?? []

        // Find the last rate limit event
        let lastRateLimit = allRecords.first(where: { $0.isRateLimited })

        // Determine current window start
        let now = Date()
        let windowStart: Date

        if let limitTime = lastRateLimit?.timestamp,
           now.timeIntervalSince(limitTime) < windowDuration {
            // We're in a window that had a rate limit — parse reset time from message or fall back to +5h
            windowStart = limitTime
            let resetMessage = lastRateLimit?.rateLimitResetMessage
            let resetTime = resetMessage.flatMap { parseResetTime(from: $0, relativeTo: limitTime) }
                ?? limitTime.addingTimeInterval(windowDuration)

            // Learn the limit: sum all tokens from this window's start going back to previous reset
            let learnedLimit = learnTokenLimit(before: limitTime, allRecords: allRecords)

            // Tokens used since the rate limit (in the new window after reset)
            let tokensSinceReset: Int
            if now >= resetTime {
                // We're past the reset — count tokens since reset
                tokensSinceReset = allRecords
                    .filter { $0.timestamp >= resetTime && $0.timestamp <= now }
                    .reduce(0) { $0 + $1.totalTokens }

                currentWindow = UsageWindow(
                    tokensUsed: tokensSinceReset,
                    learnedLimit: learnedLimit,
                    resetTime: resetTime.addingTimeInterval(windowDuration),
                    windowStart: resetTime,
                    isLimited: false
                )
            } else {
                // Still in the limited window
                currentWindow = UsageWindow(
                    tokensUsed: 0,
                    learnedLimit: learnedLimit,
                    resetTime: resetTime,
                    windowStart: windowStart,
                    isLimited: true
                )
            }
        } else {
            // No recent rate limit — estimate window from learned history
            let learnedLimit = learnTokenLimitFromHistory(allRecords: allRecords)
            let windowStartTime = now.addingTimeInterval(-windowDuration)

            let tokensInWindow = allRecords
                .filter { $0.timestamp >= windowStartTime && $0.timestamp <= now }
                .reduce(0) { $0 + $1.totalTokens }

            currentWindow = UsageWindow(
                tokensUsed: tokensInWindow,
                learnedLimit: learnedLimit,
                resetTime: nil,
                windowStart: windowStartTime,
                isLimited: false
            )
        }
    }

    /// Parse the actual reset time from a Claude rate limit message.
    ///
    /// Handles formats like:
    ///   "You're out of extra usage · resets 4am (Europe/Berlin)"
    ///   "You've hit your limit · resets 7pm (Europe/Berlin)"
    ///   "resets 4:00am (Europe/Berlin)"
    ///   "resets 16:00 (UTC)"
    ///
    /// Returns the next occurrence of that time on or after `relativeTo`.
    /// Returns nil if parsing fails (caller should fall back to +5h).
    private func parseResetTime(from message: String, relativeTo date: Date) -> Date? {
        // Pattern: resets <time> (<timezone>)
        // Time formats: 4am, 7pm, 4:00am, 16:00
        let pattern = #"resets\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(message.startIndex..., in: message)
        guard let match = regex.firstMatch(in: message, range: range) else {
            return nil
        }

        // Extract hour
        guard let hourRange = Range(match.range(at: 1), in: message),
              let hour = Int(message[hourRange]) else {
            return nil
        }

        // Extract optional minutes
        var minute = 0
        if let minRange = Range(match.range(at: 2), in: message),
           let parsedMin = Int(message[minRange]) {
            minute = parsedMin
        }

        // Extract optional am/pm
        var hour24 = hour
        if let ampmRange = Range(match.range(at: 3), in: message) {
            let ampm = message[ampmRange].lowercased()
            if ampm == "pm" && hour != 12 {
                hour24 = hour + 12
            } else if ampm == "am" && hour == 12 {
                hour24 = 0
            }
        }

        // Extract timezone
        guard let tzRange = Range(match.range(at: 4), in: message) else {
            return nil
        }
        let tzString = String(message[tzRange])
        guard let timezone = TimeZone(identifier: tzString) else {
            return nil
        }

        // Build the reset time: find the next occurrence of hour24:minute in the given timezone
        var cal = Calendar.current
        cal.timeZone = timezone

        var components = cal.dateComponents(in: timezone, from: date)
        components.hour = hour24
        components.minute = minute
        components.second = 0
        components.nanosecond = 0

        guard var candidate = cal.date(from: components) else {
            return nil
        }

        // If the candidate time is in the past relative to the rate limit event, advance by 1 day
        if candidate <= date {
            candidate = cal.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }

        return candidate
    }

    /// Learn the effective token limit by summing tokens used before the rate limit was hit
    private func learnTokenLimit(before limitTime: Date, allRecords: [TokenRecord]) -> Int {
        // Go back up to windowDuration before the rate limit
        let windowStart = limitTime.addingTimeInterval(-windowDuration)
        return allRecords
            .filter { $0.timestamp >= windowStart && $0.timestamp <= limitTime && !$0.isRateLimited }
            .reduce(0) { $0 + $1.totalTokens }
    }

    /// Learn from historical rate limit events
    private func learnTokenLimitFromHistory(allRecords: [TokenRecord]) -> Int? {
        let rateLimitEvents = allRecords.filter { $0.isRateLimited }
        guard !rateLimitEvents.isEmpty else { return nil }

        // Average the learned limits from past rate limit events
        var limits: [Int] = []
        for event in rateLimitEvents {
            let limit = learnTokenLimit(before: event.timestamp, allRecords: allRecords)
            if limit > 0 {
                limits.append(limit)
            }
        }

        guard !limits.isEmpty else { return nil }
        return limits.reduce(0, +) / limits.count
    }
}
