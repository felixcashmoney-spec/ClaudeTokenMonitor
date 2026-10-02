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

    private var totalAll: Int { filteredTokenRecords.reduce(0) { $0 + $1.totalTokens } }

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

                // Usage Limits
                sectionHeader("Nutzungslimits", icon: "chart.bar.xaxis")
                UsageLimitsCard(window: usageTracker.currentWindow)

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
        .frame(width: 380, height: 380)
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

// MARK: - Usage Limits Card

struct UsageLimitsCard: View {
    let window: UsageWindow?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            
            // 5h Usage
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 10))
                    Text("Aktuelle Sitzung (5h)")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    let util5h = window?.fiveHourUtilization ?? 0
                    Text("\(Int(util5h * 100))%")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(util5h > 0.8 ? .red : .primary)
                }
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.1))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.red)
                            .frame(width: geo.size.width * min(window?.fiveHourUtilization ?? 0, 1.0))
                    }
                }
                .frame(height: 4)
                
                if let reset = window?.fiveHourResetTime {
                    Text("Auffüllung \(formatResetDate(reset))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            
            // 7d Usage
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.red)
                        .font(.system(size: 10))
                    Text("Wöchentlich (7 Tage)")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    let util7d = window?.sevenDayUtilization ?? 0
                    Text("\(Int(util7d * 100))%")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(util7d > 0.8 ? .red : .primary)
                }
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.1))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.red)
                            .frame(width: geo.size.width * min(window?.sevenDayUtilization ?? 0, 1.0))
                    }
                }
                .frame(height: 4)
                
                if let reset = window?.sevenDayResetTime {
                    Text("Auffüllung \(formatResetDate(reset))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider().opacity(0.5)
            
            // Extra Credit / Prepaid Balance
            if window?.extraUsageEnabled == true || window?.extraUsageMonthlyLimitCents ?? 0 > 0 || window?.creditBalanceCents ?? 0 > 0 {
                let balance = window?.creditBalanceCents ?? 0
                let spent = window?.extraUsageSpentCents ?? 0
                let limit = window?.extraUsageMonthlyLimitCents ?? 0
                let eurosBalance = Double(balance) / 100.0
                let eurosSpent = Double(spent) / 100.0
                let eurosLimit = Double(limit) / 100.0
                VStack(alignment: .leading, spacing: 4) {
                    if balance > 0 {
                        HStack {
                            Text(String(format: "%.2f €", eurosBalance).replacingOccurrences(of: ".", with: ","))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.green)
                            Text("Guthaben")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Image(systemName: "creditcard.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.tint)
                        }
                    }
                    HStack {
                        Text(String(format: "%.2f € ausgegeben", eurosSpent).replacingOccurrences(of: ".", with: ","))
                        Spacer()
                        if limit > 0 {
                            Text(String(format: "Limit %.2f €", eurosLimit).replacingOccurrences(of: ".", with: ","))
                        }
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                }
            }
            
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
