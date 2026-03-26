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
                Text("Budget")
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(TokenFormatter.format(currentTokens)) / \(TokenFormatter.format(budget))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("(\(Int(percent * 100))%)")
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
        }
    }
}

struct DashboardView: View {
    @Query private var sessions: [Session]
    @Query private var budgetSettings: [BudgetSettings]
    @Environment(\.modelContext) private var modelContext
    @State private var timeFilter: TimeFilter = .today

    private var filteredSessions: [Session] {
        let cutoff = timeFilter.startDate
        return sessions.filter { $0.lastActivityAt >= cutoff }
    }

    private var totalInput: Int {
        filteredSessions.reduce(0) { $0 + $1.totalInputTokens }
    }

    private var totalOutput: Int {
        filteredSessions.reduce(0) { $0 + $1.totalOutputTokens }
    }

    private var totalCache: Int {
        filteredSessions.reduce(0) { $0 + $1.totalCacheCreationTokens + $1.totalCacheReadTokens }
    }

    private var totalAll: Int {
        filteredSessions.reduce(0) { $0 + $1.totalTokens }
    }

    private var projectBreakdown: [(name: String, tokens: Int)] {
        var byProject: [String: Int] = [:]
        for session in filteredSessions {
            byProject[session.projectName, default: 0] += session.totalTokens
        }
        return byProject.sorted { $0.value > $1.value }.map { (name: $0.key, tokens: $0.value) }
    }

    private var rateLimitEvents: Int {
        filteredSessions.reduce(0) { total, session in
            total + session.tokenRecords.filter { $0.isRateLimited && $0.timestamp >= timeFilter.startDate }.count
        }
    }

    private var latestRateLimitMessage: String? {
        sessions.compactMap { $0.lastRateLimitMessage }.last
    }

    private var monthlyTokens: Int {
        let cal = Calendar.current
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        return sessions.filter { $0.lastActivityAt >= startOfMonth }
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
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Claude Token Monitor")
                    .font(.headline)
                Spacer()
                Picker("", selection: $timeFilter) {
                    ForEach(TimeFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            Divider()

            // Total tokens — glass cards
            HStack(spacing: 10) {
                GlassStatCard(title: "Gesamt", value: TokenFormatter.format(totalAll), color: .primary)
                GlassStatCard(title: "Input", value: TokenFormatter.format(totalInput), color: .blue)
                GlassStatCard(title: "Output", value: TokenFormatter.format(totalOutput), color: .green)
                GlassStatCard(title: "Cache", value: TokenFormatter.format(totalCache), color: .orange)
            }

            // Budget banner
            if case .noBudget = budgetState {} else {
                BudgetBanner(
                    state: budgetState,
                    currentTokens: monthlyTokens,
                    budget: budgetSettings.first?.monthlyBudget ?? 0
                )
            }

            // Rate limit / plan status
            if rateLimitEvents > 0 || latestRateLimitMessage != nil {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .foregroundStyle(.red)
                        Text("Plan-Limit erreicht")
                            .font(.caption.weight(.medium))
                        if rateLimitEvents > 0 {
                            Text("(\(rateLimitEvents)x)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let msg = latestRateLimitMessage {
                        Text(msg)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            // Project breakdown
            Text("Projekte")
                .font(.subheadline.weight(.medium))

            if projectBreakdown.isEmpty {
                Text("Keine Daten für diesen Zeitraum")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(projectBreakdown, id: \.name) { project in
                            ProjectRow(
                                name: project.name,
                                tokens: project.tokens,
                                fraction: totalAll > 0 ? Double(project.tokens) / Double(totalAll) : 0
                            )
                        }
                    }
                }
                .frame(maxHeight: 120)
            }

            Divider()

            // Footer
            HStack {
                Text("\(filteredSessions.count) Sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Settings...") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding(16)
        .frame(width: 380, height: 420)
    }
}

struct GlassStatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text(TokenFormatter.format(tokens))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
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
            .frame(height: 4)
        }
    }
}
