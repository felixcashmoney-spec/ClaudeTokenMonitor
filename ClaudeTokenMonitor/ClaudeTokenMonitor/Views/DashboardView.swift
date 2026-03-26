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

struct DashboardView: View {
    @Query private var sessions: [Session]
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
        return byProject.sorted { $0.value > $1.value }
    }

    private var rateLimitEvents: Int {
        filteredSessions.reduce(0) { total, session in
            total + session.tokenRecords.filter { $0.isRateLimited && $0.timestamp >= timeFilter.startDate }.count
        }
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

            // Total tokens
            HStack(spacing: 16) {
                StatCard(title: "Gesamt", value: TokenFormatter.format(totalAll), color: .primary)
                StatCard(title: "Input", value: TokenFormatter.format(totalInput), color: .blue)
                StatCard(title: "Output", value: TokenFormatter.format(totalOutput), color: .green)
                StatCard(title: "Cache", value: TokenFormatter.format(totalCache), color: .orange)
            }

            if rateLimitEvents > 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("\(rateLimitEvents) Rate-Limit Events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        .frame(width: 360, height: 340)
    }
}

struct StatCard: View {
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
                RoundedRectangle(cornerRadius: 2)
                    .fill(.tint)
                    .frame(width: geo.size.width * fraction)
            }
            .frame(height: 4)
        }
    }
}
