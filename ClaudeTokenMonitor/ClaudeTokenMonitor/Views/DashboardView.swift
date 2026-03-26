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
    let tokenRecords: [TokenRecord]

    private let windowDuration: TimeInterval = 5 * 60 * 60

    private var lastRateLimit: TokenRecord? {
        tokenRecords
            .sorted { $0.timestamp > $1.timestamp }
            .first { $0.isRateLimited }
    }

    private var learnedLimit: Int? {
        guard let limitEvent = lastRateLimit else { return nil }
        let windowStart = limitEvent.timestamp.addingTimeInterval(-windowDuration)
        let tokensBeforeLimit = tokenRecords
            .filter { $0.timestamp >= windowStart && $0.timestamp <= limitEvent.timestamp && !$0.isRateLimited }
            .reduce(0) { $0 + $1.totalTokens }
        return tokensBeforeLimit > 0 ? tokensBeforeLimit : nil
    }

    private var tokensInCurrentWindow: Int {
        let windowStart = Date().addingTimeInterval(-windowDuration)
        return tokenRecords
            .filter { $0.timestamp >= windowStart && !$0.isRateLimited }
            .reduce(0) { $0 + $1.totalTokens }
    }

    private var isCurrentlyLimited: Bool {
        guard let limitEvent = lastRateLimit else { return false }
        let resetTime = limitEvent.timestamp.addingTimeInterval(windowDuration)
        return Date() < resetTime
    }

    private var resetTime: Date? {
        guard let limitEvent = lastRateLimit else { return nil }
        let reset = limitEvent.timestamp.addingTimeInterval(windowDuration)
        return Date() < reset ? reset : nil
    }

    var body: some View {
        if let limit = learnedLimit {
            let used = tokensInCurrentWindow
            let remaining = max(0, limit - used)
            let percent = min(1.0, Double(used) / Double(limit))
            let color: Color = isCurrentlyLimited ? .red : (percent > 0.8 ? .orange : (percent > 0.5 ? .yellow : .green))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.caption)
                        .foregroundStyle(color)
                    Text("Pro Plan Nutzung (5h-Fenster)")
                        .font(.caption.weight(.medium))
                    Spacer()
                }

                if isCurrentlyLimited {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.caption2)
                            .foregroundStyle(.red)
                        if let reset = resetTime {
                            Text("Limit erreicht — Reset um \(reset, style: .time)")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                } else {
                    HStack {
                        Text("Noch verfügbar:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("~\(TokenFormatter.format(remaining)) Tokens")
                            .font(.caption2.weight(.medium).monospacedDigit())
                            .foregroundStyle(color)
                        Spacer()
                        Text("\(Int(percent * 100))% verbraucht")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
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

                Text("Basierend auf deinem letzten Rate-Limit (~\(TokenFormatter.format(limit)) Tokens pro 5h)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
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
}

struct CurrentSessionBanner: View {
    let session: Session

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
            Text("Letzte Aktivitaet: \(session.lastActivityAt, style: .relative) zurueck")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct DashboardView: View {
    @Query private var sessions: [Session]
    @Query private var budgetSettings: [BudgetSettings]
    @Query private var allTokenRecords: [TokenRecord]
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

    private var currentSession: Session? {
        sessions.sorted { $0.lastActivityAt > $1.lastActivityAt }.first
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
                PlanUsageBanner(tokenRecords: allTokenRecords)

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
