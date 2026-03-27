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
            // We're in a window that had a rate limit — window resets after ~5h
            windowStart = limitTime
            let resetTime = limitTime.addingTimeInterval(windowDuration)

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
