import SwiftUI
import SwiftData

enum TimeFilter: String, CaseIterable {
    case today = "Heute"
    case week = "Woche"
    case month = "Monat"

    var startDate: Date {
        let cal = Calendar.current
        switch self {
        case .today: return cal.startOfDay(for: Date())
        case .week: return cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        case .month: return cal.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        }
    }
}

struct BudgetBanner: View {
    let state: BudgetState
    let currentTokens: Int
    let budget: Int

    var body: some View {
        switch state {
        case .noBudget:
            EmptyView()
        case .ok(let pct):
            budgetBar(percent: pct, color: .green)
        case .warning(let pct, _):
            budgetBar(percent: pct, color: .yellow)
        case .critical(let pct, _):
            budgetBar(percent: pct, color: .orange)
        case .exceeded(let pct):
            budgetBar(percent: min(pct, 1.0), color: .red)
        }
    }

    @ViewBuilder
    private func budgetBar(percent: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "creditcard")
                    .font(.caption2)
                    .foregroundStyle(color)
                Text("Dein monatliches Budget")
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(Int(percent * 100))% verbraucht")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * min(percent, 1.0))
                }
            }
            .frame(height: 6)
            Text("\(TokenFormatter.format(currentTokens)) von \(TokenFormatter.format(budget)) Tokens verwendet")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct PlanUsageBanner: View {
    let window: UsageWindow?

    var body: some View {
        if let window, window.fiveHourUtilization != nil || window.learnedLimit != nil {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Plan-Nutzungslimits")
                        .font(.caption.weight(.semibold))
                }

                // 5h window
                windowBar(
                    label: "Aktuelle Sitzung",
                    utilization: window.fiveHourUtilization,
                    tokensUsed: window.tokensUsed,
                    learnedLimit: window.learnedLimit,
                    status: window.fiveHourStatus,
                    resetTime: window.fiveHourResetTime,
                    isLimited: window.isLimited
                )

                // 7d window (only shown when log data is available)
                if let util7d = window.sevenDayUtilization {
                    Divider()

                    windowBar(
                        label: "Wöchentliche Limits",
                        utilization: util7d,
                        tokensUsed: nil,
                        learnedLimit: nil,
                        status: window.sevenDayStatus,
                        resetTime: window.sevenDayResetTime,
                        isLimited: window.sevenDayStatus == "exceeded_limit"
                    )
                }

                // Extra usage status banner
                extraUsageBanner(window: window)

                // Footer
                if window.fiveHourUtilization != nil {
                    Text("Basierend auf Claude Rate-Limit Daten")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                } else if let limit = window.learnedLimit {
                    Text("Basierend auf deinem letzten Rate-Limit (~\(TokenFormatter.format(limit)) Tokens pro 5h)")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Pro Plan Nutzung")
                        .font(.caption.weight(.medium))
                }
                Text("Noch kein Rate-Limit erkannt. Sobald du einmal ans Limit kommst, lernt die App dein verfügbares Kontingent und zeigt den Restverbrauch an.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func windowBar(
        label: String,
        utilization: Double?,
        tokensUsed: Int?,
        learnedLimit: Int?,
        status: String?,
        resetTime: Date?,
        isLimited: Bool
    ) -> some View {
        let percent = utilization.map { min(1.0, $0) } ?? {
            guard let used = tokensUsed, let limit = learnedLimit, limit > 0 else { return 0.0 }
            return min(1.0, Double(used) / Double(limit))
        }()
        let color: Color = isLimited ? .red : (percent > 0.8 ? .orange : (percent > 0.5 ? .yellow : .green))

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                Spacer()
                if let util = utilization {
                    Text("\(Int(util * 100)) % verwendet")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(color)
                } else {
                    Text("\(Int(percent * 100)) % verwendet")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(color)
                }
            }

            if isLimited, let reset = resetTime {
                Text("Zurücksetzung in \(reset, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let util = utilization, util < 1.0 {
                let remainingPct = max(0, Int((1.0 - util) * 100))
                HStack {
                    Text("Noch \(remainingPct)% verfügbar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let reset = resetTime {
                        Spacer()
                        Text("Zurücksetzung in \(reset, style: .relative)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else if let remaining = {
                guard let used = tokensUsed, let limit = learnedLimit else { return nil as Int? }
                return max(0, limit - used)
            }(), utilization == nil {
                HStack {
                    Text("Noch verfügbar:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("~\(TokenFormatter.format(remaining)) Tokens")
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(color)
                    Spacer()
                }
            } else if let reset = resetTime, !isLimited {
                Text("Zurücksetzung in \(reset, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * percent)
                }
            }
            .frame(height: 6)
        }
    }

    @ViewBuilder
    private func extraUsageBanner(window: UsageWindow) -> some View {
        let hasOverageInfo = window.overageDisabledReason != nil || window.overageInUse

        if hasOverageInfo {
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "creditcard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Zusätzliche Nutzung")
                        .font(.caption.weight(.semibold))
                }

                if let reason = window.overageDisabledReason {
                    if reason == "out_of_credits" {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text("Guthaben aufgebraucht")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    } else if reason == "org_level_disabled" {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("Nicht aktiviert")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }
                } else if window.overageInUse {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        Text("Extra Usage aktiv — Guthaben wird verwendet")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.blue)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
}

struct CurrentSessionBanner: View {
    let session: Session
    @State private var dotOpacity: Double = 1.0

    private var sessionDuration: String {
        let elapsed = Date().timeIntervalSince(session.createdAt)
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row
            HStack {
                // Pulsing green dot to indicate "live"
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                    .opacity(dotOpacity)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                            dotOpacity = 0.2
                        }
                    }
                Image(systemName: "terminal")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text(session.projectName)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Spacer()
                Text("seit \(sessionDuration)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Token stats row
            HStack {
                VStack(spacing: 2) {
                    Text(TokenFormatter.format(session.totalTokens))
                        .font(.caption2.monospacedDigit())
                    Text("Gesamt")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(TokenFormatter.format(session.totalInputTokens))
                        .font(.caption2.monospacedDigit())
                    Text("Input")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(TokenFormatter.format(session.totalOutputTokens))
                        .font(.caption2.monospacedDigit())
                    Text("Output")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            // Activity indicator
            Text("Letzte Aktivität: \(session.lastActivityAt, style: .relative) zurück")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(.green.opacity(0.05))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .leading) {
            // Green left border accent
            Rectangle()
                .fill(.green)
                .frame(width: 3)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 10,
                        bottomLeadingRadius: 10,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )
        }
    }
}

struct DashboardView: View {
    @Query private var sessions: [Session]
    @Query private var allTokenRecords: [TokenRecord]
    @Query private var budgetSettings: [BudgetSettings]
    @EnvironmentObject private var usageTracker: UsageWindowTracker
    @Environment(\.modelContext) private var modelContext
    @State private var timeFilter: TimeFilter = .today

    /// Sessions active within the time window (used for session count and project breakdown)
    private var filteredSessions: [Session] {
        let cutoff = timeFilter.startDate
        return sessions.filter { $0.lastActivityAt >= cutoff }
    }

    /// Token records with timestamps within the time window (authoritative for token sums)
    private var filteredTokenRecords: [TokenRecord] {
        let cutoff = timeFilter.startDate
        return allTokenRecords.filter { $0.timestamp >= cutoff }
    }

    private var totalInput: Int {
        filteredTokenRecords.reduce(0) { $0 + $1.inputTokens }
    }

    private var totalOutput: Int {
        filteredTokenRecords.reduce(0) { $0 + $1.outputTokens }
    }

    private var totalCache: Int {
        filteredTokenRecords.reduce(0) { $0 + $1.cacheCreationInputTokens + $1.cacheReadInputTokens }
    }

    private var totalCacheCreation: Int {
        filteredTokenRecords.reduce(0) { $0 + $1.cacheCreationInputTokens }
    }

    private var totalCacheRead: Int {
        filteredTokenRecords.reduce(0) { $0 + $1.cacheReadInputTokens }
    }

    /// Estimated API cost in USD using Claude Sonnet 4 pricing.
    /// Note: Pro Plan users don't pay per-token — this is a "what it would cost" reference value.
    private var estimatedCost: Double {
        (Double(totalInput) * 3.0
            + Double(totalOutput) * 15.0
            + Double(totalCacheCreation) * 3.75
            + Double(totalCacheRead) * 0.30) / 1_000_000
    }

    private var totalAll: Int {
        filteredTokenRecords.reduce(0) { $0 + $1.totalTokens }
    }

    private var projectBreakdown: [(name: String, tokens: Int)] {
        // Use token records with timestamps in range, grouped by their session's project name
        var byProject: [String: Int] = [:]
        for record in filteredTokenRecords {
            let projectName = record.session?.projectName ?? "Unknown"
            byProject[projectName, default: 0] += record.totalTokens
        }
        return byProject.sorted { $0.value > $1.value }.map { (name: $0.key, tokens: $0.value) }
    }

    private var rateLimitEvents: Int {
        filteredTokenRecords.filter { $0.isRateLimited }.count
    }

    private var latestRateLimitMessage: String? {
        sessions.compactMap { $0.lastRateLimitMessage }.last
    }

    private var currentSession: Session? {
        sessions.sorted { $0.lastActivityAt > $1.lastActivityAt }.first
    }

    private var monthlyTokens: Int {
        let cal = Calendar.current
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        return allTokenRecords
            .filter { $0.timestamp >= startOfMonth }
            .reduce(0) { $0 + $1.totalTokens }
    }

    private var budgetState: BudgetState {
        guard let settings = budgetSettings.first, settings.monthlyBudget > 0 else {
            return .noBudget
        }
        let usage = Double(monthlyTokens) / Double(settings.monthlyBudget)
        if usage >= 1.0 { return .exceeded(usagePercent: usage) }
        if usage >= settings.warningThreshold2 { return .critical(usagePercent: usage, threshold: settings.warningThreshold2) }
        if usage >= settings.warningThreshold1 { return .warning(usagePercent: usage, threshold: settings.warningThreshold1) }
        return .ok(usagePercent: usage)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claude Token Monitor")
                            .font(.headline)
                        Text("Dein Claude Code Verbrauch auf einen Blick")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $timeFilter) {
                        ForEach(TimeFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }

                // Current session banner
                if let session = currentSession {
                    CurrentSessionBanner(session: session)
                }

                // Plan usage — shows remaining tokens in current 5h window
                PlanUsageBanner(window: usageTracker.currentWindow)

                Divider()

                // Section: Token-Verbrauch
                Text("Token-Verbrauch")
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 10) {
                    GlassStatCard(
                        title: "Gesamt",
                        subtitle: "Alle Tokens",
                        value: TokenFormatter.format(totalAll),
                        color: .primary
                    )
                    GlassStatCard(
                        title: "Input",
                        subtitle: "Deine Prompts",
                        value: TokenFormatter.format(totalInput),
                        color: .blue
                    )
                    GlassStatCard(
                        title: "Output",
                        subtitle: "Claudes Antworten",
                        value: TokenFormatter.format(totalOutput),
                        color: .green
                    )
                    GlassStatCard(
                        title: "Cache",
                        subtitle: "Zwischengespeichert",
                        value: TokenFormatter.format(totalCache),
                        color: .orange
                    )
                }

                // Estimated API cost row
                HStack {
                    Image(systemName: "dollarsign.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Geschätzter API-Wert: $\(String(format: "%.2f", estimatedCost))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("(Sonnet 4 Preise)")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }

                // Budget banner
                if case .noBudget = budgetState {} else {
                    BudgetBanner(
                        state: budgetState,
                        currentTokens: monthlyTokens,
                        budget: budgetSettings.first?.monthlyBudget ?? 0
                    )
                }

                Divider()

                // Section: Projekte
                VStack(alignment: .leading, spacing: 4) {
                    Text("Verbrauch pro Projekt")
                        .font(.subheadline.weight(.medium))
                    Text("Welches Projekt verbraucht wie viele Tokens")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if projectBreakdown.isEmpty {
                    Text("Keine Daten für diesen Zeitraum")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        ForEach(projectBreakdown, id: \.name) { project in
                            ProjectRow(
                                name: project.name,
                                tokens: project.tokens,
                                fraction: totalAll > 0 ? Double(project.tokens) / Double(totalAll) : 0,
                                percent: totalAll > 0 ? Int(Double(project.tokens) / Double(totalAll) * 100) : 0
                            )
                        }
                    }
                }

                Divider()

                // Footer
                HStack {
                    Text("\(filteredSessions.count) Sessions im Zeitraum")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Einstellungen...") {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                        NSApp.keyWindow?.close()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            .padding(16)
        }
        .frame(width: 400, height: 500)
        .environment(\.locale, Locale(identifier: "de_DE"))
    }
}

struct GlassStatCard: View {
    let title: String
    let subtitle: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption2.weight(.medium))
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ProjectRow: View {
    let name: String
    let tokens: Int
    let fraction: Double
    let percent: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "folder.fill")
                    .font(.caption2)
                    .foregroundStyle(.tint)
                Text(name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(TokenFormatter.format(tokens))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("(\(percent)%)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.tint)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 5)
        }
        .padding(.vertical, 2)
    }
}
