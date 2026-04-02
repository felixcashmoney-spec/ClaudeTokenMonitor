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

// MARK: - Helper formatters

private func formatEUR(cents: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "EUR"
    formatter.locale = Locale(identifier: "de_DE")
    return formatter.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "\(Double(cents) / 100.0) EUR"
}

private func formatResetDate(_ date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "'heute,' HH:mm"
        return f.string(from: date)
    } else if cal.isDateInTomorrow(date) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "'morgen,' HH:mm"
        return f.string(from: date)
    } else {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "E., HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Usage Limits Section

struct UsageLimitsCard: View {
    let window: UsageWindow?

    var body: some View {
        if let window, window.fiveHourUtilization != nil || window.sevenDayUtilization != nil || window.learnedLimit != nil {
            VStack(alignment: .leading, spacing: 0) {
                // 5h window
                if window.fiveHourUtilization != nil || window.learnedLimit != nil {
                    usageRow(
                        icon: "bolt.fill",
                        label: "Aktuelle Sitzung (5h)",
                        utilization: window.fiveHourUtilization,
                        tokensUsed: window.tokensUsed,
                        learnedLimit: window.learnedLimit,
                        resetTime: window.fiveHourResetTime,
                        isLimited: window.isLimited
                    )
                }

                // 7d window
                if let util7d = window.sevenDayUtilization {
                    if window.fiveHourUtilization != nil || window.learnedLimit != nil {
                        Divider().padding(.vertical, 8)
                    }
                    usageRow(
                        icon: "calendar",
                        label: "Wöchentlich (7 Tage)",
                        utilization: util7d,
                        tokensUsed: nil,
                        learnedLimit: nil,
                        resetTime: window.sevenDayResetTime,
                        isLimited: window.sevenDayStatus == "exceeded_limit"
                    )
                }

                // Next API update
                if let freshness = window.apiDataFreshness {
                    let nextUpdate = freshness.addingTimeInterval(120)
                    Divider().padding(.vertical, 6)
                    HStack {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                        Text("Nächste Aktualisierung \(nextUpdate, style: .relative)")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        } else {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Noch keine Nutzungsdaten verfügbar")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func usageRow(
        icon: String,
        label: String,
        utilization: Double?,
        tokensUsed: Int?,
        learnedLimit: Int?,
        resetTime: Date?,
        isLimited: Bool
    ) -> some View {
        let percent = utilization.map { min(1.0, $0) } ?? {
            guard let used = tokensUsed, let limit = learnedLimit, limit > 0 else { return 0.0 }
            return min(1.0, Double(used) / Double(limit))
        }()
        let color: Color = isLimited ? .red : (percent > 0.8 ? .orange : (percent > 0.5 ? .yellow : .blue))

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                    .frame(width: 14)
                Text(label)
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(Int((utilization ?? percent) * 100))%")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * percent)
                }
            }
            .frame(height: 6)

            // Reset info
            if let reset = resetTime {
                Text("Zurücksetzung \(formatResetDate(reset))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Credits & Spending Section

struct CreditsCard: View {
    let window: UsageWindow?

    var body: some View {
        if let window, let balance = window.creditBalanceCents {
            VStack(alignment: .leading, spacing: 8) {
                // Balance
                HStack(alignment: .firstTextBaseline) {
                    Text(formatEUR(cents: balance))
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(balance > 0 ? .green : .red)
                    Text("Guthaben")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if window.extraUsageEnabled == true {
                        Image(systemName: "bolt.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                if let spent = window.extraUsageSpentCents, window.extraUsageEnabled == true {
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ausgegeben")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(formatEUR(cents: spent))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(spent > 0 ? .orange : .secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Monatslimit")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            if let limit = window.extraUsageMonthlyLimitCents {
                                Text(formatEUR(cents: limit))
                                    .font(.caption.weight(.semibold).monospacedDigit())
                            } else {
                                Text("Unbegrenzt")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else if window.extraUsageEnabled == false {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 10))
                        Text("Extra Usage nicht aktiviert")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        } else if let window, let reason = window.overageDisabledReason {
            HStack(spacing: 6) {
                Image(systemName: reason == "out_of_credits" ? "exclamationmark.triangle.fill" : "xmark.circle")
                    .foregroundStyle(reason == "out_of_credits" ? .orange : .secondary)
                Text(reason == "out_of_credits" ? "Guthaben aufgebraucht" : "Extra Usage nicht aktiviert")
                    .font(.caption)
                    .foregroundStyle(reason == "out_of_credits" ? .orange : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Token Stats Section

struct TokenStatsSection: View {
    let totalAll: Int
    let totalInput: Int
    let totalOutput: Int
    let totalCache: Int
    let estimatedCost: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statCard("Gesamt", value: TokenFormatter.format(totalAll), color: .primary)
                statCard("Input", value: TokenFormatter.format(totalInput), color: .blue)
                statCard("Output", value: TokenFormatter.format(totalOutput), color: .green)
                statCard("Cache", value: TokenFormatter.format(totalCache), color: .orange)
            }

            HStack {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("API-Wert: ~$\(String(format: "%.2f", estimatedCost))")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
                Text("(Sonnet 4)")
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            }
        }
    }

    private func statCard(_ title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Project Breakdown

struct ProjectBreakdownSection: View {
    let projects: [(name: String, tokens: Int)]
    let totalTokens: Int

    var body: some View {
        if projects.isEmpty {
            Text("Keine Daten")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
        } else {
            VStack(spacing: 6) {
                ForEach(projects, id: \.name) { project in
                    let fraction = totalTokens > 0 ? Double(project.tokens) / Double(totalTokens) : 0
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tint)
                            .frame(width: 14)
                        Text(project.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(TokenFormatter.format(project.tokens))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("\(Int(fraction * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 28, alignment: .trailing)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.quaternary)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.tint)
                                .frame(width: geo.size.width * fraction)
                        }
                    }
                    .frame(height: 3)
                }
            }
        }
    }
}

// MARK: - Budget Banner

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
                Text("Monatsbudget")
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(Int(percent * 100))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
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
            Text("\(TokenFormatter.format(currentTokens)) / \(TokenFormatter.format(budget))")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Dashboard View

struct DashboardView: View {
    @Query private var sessions: [Session]
    @Query private var allTokenRecords: [TokenRecord]
    @Query private var budgetSettings: [BudgetSettings]
    @EnvironmentObject private var usageTracker: UsageWindowTracker
    @Environment(\.modelContext) private var modelContext
    @State private var timeFilter: TimeFilter = .today

    private var filteredSessions: [Session] {
        let cutoff = timeFilter.startDate
        return sessions.filter { $0.lastActivityAt >= cutoff }
    }

    private var filteredTokenRecords: [TokenRecord] {
        let cutoff = timeFilter.startDate
        return allTokenRecords.filter { $0.timestamp >= cutoff }
    }

    private var totalInput: Int { filteredTokenRecords.reduce(0) { $0 + $1.inputTokens } }
    private var totalOutput: Int { filteredTokenRecords.reduce(0) { $0 + $1.outputTokens } }
    private var totalCache: Int { filteredTokenRecords.reduce(0) { $0 + $1.cacheCreationInputTokens + $1.cacheReadInputTokens } }
    private var totalAll: Int { filteredTokenRecords.reduce(0) { $0 + $1.totalTokens } }

    private var estimatedCost: Double {
        let cacheCreation = filteredTokenRecords.reduce(0) { $0 + $1.cacheCreationInputTokens }
        let cacheRead = filteredTokenRecords.reduce(0) { $0 + $1.cacheReadInputTokens }
        return (Double(totalInput) * 3.0 + Double(totalOutput) * 15.0
            + Double(cacheCreation) * 3.75 + Double(cacheRead) * 0.30) / 1_000_000
    }

    private var projectBreakdown: [(name: String, tokens: Int)] {
        var byProject: [String: Int] = [:]
        for record in filteredTokenRecords {
            let name = record.session?.projectName ?? "Unknown"
            byProject[name, default: 0] += record.totalTokens
        }
        return byProject.sorted { $0.value > $1.value }.map { (name: $0.key, tokens: $0.value) }
    }

    private var monthlyTokens: Int {
        let cal = Calendar.current
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        return allTokenRecords.filter { $0.timestamp >= startOfMonth }.reduce(0) { $0 + $1.totalTokens }
    }

    private var budgetState: BudgetState {
        guard let settings = budgetSettings.first, settings.monthlyBudget > 0 else { return .noBudget }
        let usage = Double(monthlyTokens) / Double(settings.monthlyBudget)
        if usage >= 1.0 { return .exceeded(usagePercent: usage) }
        if usage >= settings.warningThreshold2 { return .critical(usagePercent: usage, threshold: settings.warningThreshold2) }
        if usage >= settings.warningThreshold1 { return .warning(usagePercent: usage, threshold: settings.warningThreshold1) }
        return .ok(usagePercent: usage)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Text("Claude Token Monitor")
                        .font(.headline)
                    Spacer()
                    Picker("", selection: $timeFilter) {
                        ForEach(TimeFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }

                // Usage limits + Credits side by side or stacked
                sectionHeader("Nutzungslimits", icon: "chart.bar.xaxis")
                UsageLimitsCard(window: usageTracker.currentWindow)
                CreditsCard(window: usageTracker.currentWindow)

                // Token stats
                sectionHeader("Token-Verbrauch", icon: "number")
                TokenStatsSection(
                    totalAll: totalAll,
                    totalInput: totalInput,
                    totalOutput: totalOutput,
                    totalCache: totalCache,
                    estimatedCost: estimatedCost
                )

                // Budget
                if case .noBudget = budgetState {} else {
                    BudgetBanner(
                        state: budgetState,
                        currentTokens: monthlyTokens,
                        budget: budgetSettings.first?.monthlyBudget ?? 0
                    )
                }

                // Projects
                sectionHeader("Projekte", icon: "folder")
                ProjectBreakdownSection(projects: projectBreakdown, totalTokens: totalAll)

                // Footer
                HStack {
                    Text("\(filteredSessions.count) Sessions")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Einstellungen") {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                        NSApp.keyWindow?.close()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
                }
                .padding(.top, 2)
            }
            .padding(14)
        }
        .frame(width: 380, height: 460)
        .environment(\.locale, Locale(identifier: "de_DE"))
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }
}
