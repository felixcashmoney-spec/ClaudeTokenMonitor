import Foundation
import SwiftData
import Combine

struct UsageWindow {
    // 5h window (authoritative from log, or estimated from tokens)
    let fiveHourUtilization: Double?    // 0.0-1.0+ from log
    let fiveHourResetTime: Date?        // exact from log
    let fiveHourStatus: String?         // "exceeded_limit" or "within_limit"

    // 7d window (from log only)
    let sevenDayUtilization: Double?
    let sevenDayResetTime: Date?
    let sevenDayStatus: String?

    // Extra usage
    let overageDisabledReason: String?  // "out_of_credits", "org_level_disabled", nil
    let overageInUse: Bool

    // Legacy fields for token-based estimates
    let tokensUsed: Int
    let learnedLimit: Int?
    let isLimited: Bool

    var remaining: Int? {
        guard let limit = learnedLimit else { return nil }
        return max(0, limit - tokensUsed)
    }

    var usagePercent: Double? {
        // Prefer authoritative log utilization
        if let util = fiveHourUtilization {
            return util
        }
        // Fall back to token-based estimate
        guard let limit = learnedLimit, limit > 0 else { return nil }
        return Double(tokensUsed) / Double(limit)
    }
}

@MainActor
final class UsageWindowTracker: ObservableObject {
    @Published var currentWindow: UsageWindow?

    private var modelContext: ModelContext?
    private var timer: Timer?
    private var logFileParser: LogFileParser?
    private var logParserCancellable: AnyCancellable?

    /// Claude Pro resets usage in ~5 hour windows
    private let windowDuration: TimeInterval = 5 * 60 * 60
    /// Log data is considered "fresh" if it's within the last 6 hours
    private let logDataFreshnessInterval: TimeInterval = 6 * 60 * 60

    func start(modelContext: ModelContext) {
        self.modelContext = modelContext

        // Start the log file parser
        let parser = LogFileParser()
        logFileParser = parser

        // Subscribe to parser updates to trigger re-evaluation
        logParserCancellable = parser.$latestInfo
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.evaluate()
            }

        parser.start()
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
        logFileParser?.stop()
        logFileParser = nil
        logParserCancellable = nil
    }

    func evaluate() {
        let now = Date()

        // Strategy: combine data from BOTH sources
        // 1. Desktop log gives: exact utilization %, 7d window, overage status
        // 2. JSONL session data gives: most recent rate limit message with reset time
        // The JSONL data is often MORE recent (Claude Code runs update it live)

        let logInfo = logFileParser?.latestInfo
        let logIsFresh = logInfo.map { now.timeIntervalSince($0.timestamp) < logDataFreshnessInterval } ?? false

        // Get the most recent rate limit from JSONL sessions
        let sessionResetInfo = findLatestSessionRateLimit(now: now)

        if logIsFresh, let logInfo {
            // We have log data — use it as base, but override reset time from JSONL if newer
            evaluateFromLogData(logInfo, sessionResetInfo: sessionResetInfo, now: now)
        } else if let sessionResetInfo {
            // No fresh log data, but we have JSONL rate limit info
            // Still use log data for 7d/overage if available (even if "stale")
            evaluateFromSessionRateLimit(sessionResetInfo, logInfo: logInfo, now: now)
        } else {
            // Fall back to token-based estimation
            evaluateFromTokens(now: now)
        }
    }

    /// Find the most recent rate limit message from JSONL sessions
    private func findLatestSessionRateLimit(now: Date) -> (resetTime: Date, message: String, timestamp: Date)? {
        guard let modelContext else { return nil }

        let descriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\.lastActivityAt, order: .reverse)]
        )
        let sessions = (try? modelContext.fetch(descriptor)) ?? []

        // Find the most recent rate limit message across all sessions
        var latestMsg: String?
        var latestTimestamp: Date?

        for session in sessions {
            if let msg = session.lastRateLimitMessage {
                // Check token records for the timestamp of the rate limit
                let rateLimitRecords = session.tokenRecords
                    .filter { $0.isRateLimited }
                    .sorted { $0.timestamp > $1.timestamp }

                if let latestRecord = rateLimitRecords.first {
                    if latestTimestamp == nil || latestRecord.timestamp > latestTimestamp! {
                        latestMsg = msg
                        latestTimestamp = latestRecord.timestamp
                    }
                }
            }
        }

        guard let msg = latestMsg, let ts = latestTimestamp else { return nil }
        guard let resetTime = parseResetTime(from: msg, relativeTo: ts) else { return nil }
        // Only return if reset is still in the future
        guard resetTime > now else { return nil }
        return (resetTime: resetTime, message: msg, timestamp: ts)
    }

    // MARK: - Log-based evaluation

    private func evaluateFromLogData(_ logInfo: RateLimitInfo, sessionResetInfo: (resetTime: Date, message: String, timestamp: Date)?, now: Date) {
        let fiveHour = logInfo.fiveHourWindow
        let sevenDay = logInfo.sevenDayWindow

        // Use the MOST RECENT reset time: compare log vs JSONL
        let effectiveResetTime: Date
        if let sessionInfo = sessionResetInfo, sessionInfo.timestamp > logInfo.timestamp {
            // JSONL has newer data
            effectiveResetTime = sessionInfo.resetTime
        } else {
            effectiveResetTime = fiveHour.resetsAt
        }

        let isLimited = now < effectiveResetTime

        let tokenWindow = buildTokenWindow(now: now)

        currentWindow = UsageWindow(
            fiveHourUtilization: isLimited ? max(fiveHour.utilization, 1.0) : fiveHour.utilization,
            fiveHourResetTime: effectiveResetTime,
            fiveHourStatus: isLimited ? "exceeded_limit" : fiveHour.status,
            sevenDayUtilization: sevenDay.utilization,
            sevenDayResetTime: sevenDay.resetsAt,
            sevenDayStatus: sevenDay.status,
            overageDisabledReason: logInfo.overageDisabledReason,
            overageInUse: logInfo.overageInUse,
            tokensUsed: tokenWindow?.tokensUsed ?? 0,
            learnedLimit: tokenWindow?.learnedLimit,
            isLimited: isLimited
        )
    }

    /// Evaluate using JSONL rate limit data, enriched with desktop log for 7d/overage
    private func evaluateFromSessionRateLimit(_ info: (resetTime: Date, message: String, timestamp: Date), logInfo: RateLimitInfo?, now: Date) {
        let isLimited = now < info.resetTime
        let tokenWindow = buildTokenWindow(now: now)

        // Use desktop log for 7d window and overage even if the 5h reset is stale
        let sevenDay = logInfo?.sevenDayWindow
        let overage = logInfo

        currentWindow = UsageWindow(
            fiveHourUtilization: isLimited ? 1.0 : nil,
            fiveHourResetTime: info.resetTime,
            fiveHourStatus: isLimited ? "exceeded_limit" : "within_limit",
            sevenDayUtilization: sevenDay?.utilization,
            sevenDayResetTime: sevenDay?.resetsAt,
            sevenDayStatus: sevenDay?.status,
            overageDisabledReason: overage?.overageDisabledReason,
            overageInUse: overage?.overageInUse ?? false,
            tokensUsed: tokenWindow?.tokensUsed ?? 0,
            learnedLimit: tokenWindow?.learnedLimit,
            isLimited: isLimited
        )
    }

    // MARK: - Token-based evaluation (fallback)

    private func evaluateFromTokens(now: Date) {
        guard let window = buildTokenWindow(now: now) else {
            // No data at all
            currentWindow = UsageWindow(
                fiveHourUtilization: nil,
                fiveHourResetTime: nil,
                fiveHourStatus: nil,
                sevenDayUtilization: nil,
                sevenDayResetTime: nil,
                sevenDayStatus: nil,
                overageDisabledReason: nil,
                overageInUse: false,
                tokensUsed: 0,
                learnedLimit: nil,
                isLimited: false
            )
            return
        }

        currentWindow = UsageWindow(
            fiveHourUtilization: window.usagePercent,
            fiveHourResetTime: window.resetTime,
            fiveHourStatus: window.isLimited ? "exceeded_limit" : "within_limit",
            sevenDayUtilization: nil,
            sevenDayResetTime: nil,
            sevenDayStatus: nil,
            overageDisabledReason: nil,
            overageInUse: false,
            tokensUsed: window.tokensUsed,
            learnedLimit: window.learnedLimit,
            isLimited: window.isLimited
        )
    }

    private func buildTokenWindow(now: Date) -> (tokensUsed: Int, learnedLimit: Int?, resetTime: Date?, isLimited: Bool, usagePercent: Double?)? {
        guard let modelContext else { return nil }

        let allRecordsDescriptor = FetchDescriptor<TokenRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let allRecords = (try? modelContext.fetch(allRecordsDescriptor)) ?? []
        guard !allRecords.isEmpty else { return nil }

        // Find the last rate limit event
        let lastRateLimit = allRecords.first(where: { $0.isRateLimited })

        if let limitTime = lastRateLimit?.timestamp,
           now.timeIntervalSince(limitTime) < windowDuration {
            let resetMessage = lastRateLimit?.rateLimitResetMessage
            let resetTime = resetMessage.flatMap { parseResetTime(from: $0, relativeTo: limitTime) }
                ?? limitTime.addingTimeInterval(windowDuration)
            let learnedLimit = learnTokenLimit(before: limitTime, allRecords: allRecords)

            if now >= resetTime {
                // Past the reset — count tokens since reset
                let tokensSinceReset = allRecords
                    .filter { $0.timestamp >= resetTime && $0.timestamp <= now }
                    .reduce(0) { $0 + $1.totalTokens }
                let percent = learnedLimit > 0 ? Double(tokensSinceReset) / Double(learnedLimit) : nil
                return (
                    tokensUsed: tokensSinceReset,
                    learnedLimit: learnedLimit > 0 ? learnedLimit : nil,
                    resetTime: resetTime.addingTimeInterval(windowDuration),
                    isLimited: false,
                    usagePercent: percent
                )
            } else {
                // Still limited
                let percent = learnedLimit > 0 ? 1.0 : nil
                return (
                    tokensUsed: 0,
                    learnedLimit: learnedLimit > 0 ? learnedLimit : nil,
                    resetTime: resetTime,
                    isLimited: true,
                    usagePercent: percent
                )
            }
        } else {
            // No recent rate limit — estimate
            let learnedLimit = learnTokenLimitFromHistory(allRecords: allRecords)
            let windowStartTime = now.addingTimeInterval(-windowDuration)
            let tokensInWindow = allRecords
                .filter { $0.timestamp >= windowStartTime && $0.timestamp <= now }
                .reduce(0) { $0 + $1.totalTokens }
            let percent = learnedLimit.map { lim in lim > 0 ? Double(tokensInWindow) / Double(lim) : nil } ?? nil
            return (
                tokensUsed: tokensInWindow,
                learnedLimit: learnedLimit,
                resetTime: nil,
                isLimited: false,
                usagePercent: percent
            )
        }
    }

    // MARK: - Helpers

    private func parseResetTime(from message: String, relativeTo date: Date) -> Date? {
        let pattern = #"resets\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(message.startIndex..., in: message)
        guard let match = regex.firstMatch(in: message, range: range) else { return nil }

        guard let hourRange = Range(match.range(at: 1), in: message),
              let hour = Int(message[hourRange]) else { return nil }

        var minute = 0
        if let minRange = Range(match.range(at: 2), in: message),
           let parsedMin = Int(message[minRange]) {
            minute = parsedMin
        }

        var hour24 = hour
        if let ampmRange = Range(match.range(at: 3), in: message) {
            let ampm = message[ampmRange].lowercased()
            if ampm == "pm" && hour != 12 { hour24 = hour + 12 }
            else if ampm == "am" && hour == 12 { hour24 = 0 }
        }

        guard let tzRange = Range(match.range(at: 4), in: message) else { return nil }
        let tzString = String(message[tzRange])
        guard let timezone = TimeZone(identifier: tzString) else { return nil }

        var cal = Calendar.current
        cal.timeZone = timezone
        var components = cal.dateComponents(in: timezone, from: date)
        components.hour = hour24
        components.minute = minute
        components.second = 0
        components.nanosecond = 0

        guard var candidate = cal.date(from: components) else { return nil }
        if candidate <= date {
            candidate = cal.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }

    private func learnTokenLimit(before limitTime: Date, allRecords: [TokenRecord]) -> Int {
        let windowStart = limitTime.addingTimeInterval(-windowDuration)
        return allRecords
            .filter { $0.timestamp >= windowStart && $0.timestamp <= limitTime && !$0.isRateLimited }
            .reduce(0) { $0 + $1.totalTokens }
    }

    private func learnTokenLimitFromHistory(allRecords: [TokenRecord]) -> Int? {
        let rateLimitEvents = allRecords.filter { $0.isRateLimited }
        guard !rateLimitEvents.isEmpty else { return nil }

        var limits: [Int] = []
        for event in rateLimitEvents {
            let limit = learnTokenLimit(before: event.timestamp, allRecords: allRecords)
            if limit > 0 { limits.append(limit) }
        }

        guard !limits.isEmpty else { return nil }
        return limits.reduce(0, +) / limits.count
    }
}
