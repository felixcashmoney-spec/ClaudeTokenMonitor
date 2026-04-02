import SwiftUI

// MARK: - Color helpers for usage percentage

private func usageColor(for utilization: Double?) -> Color {
    guard let util = utilization else { return .gray }
    if util >= 0.95 { return .red }
    if util >= 0.80 { return .orange }
    if util >= 0.50 { return .yellow }
    return .green
}

// MARK: - Time formatting helpers

private func formatSessionTimeLeft(resetTime: Date?, now: Date) -> String {
    guard let reset = resetTime else { return "--" }
    let remaining = reset.timeIntervalSince(now)
    guard remaining > 0 else { return "Abgelaufen" }
    let hours = Int(remaining) / 3600
    let minutes = (Int(remaining) % 3600) / 60
    if hours > 0 {
        return "\(hours)h \(minutes)m"
    }
    return "\(minutes)m"
}

private func formatWeeklyTimeLeft(resetTime: Date?, now: Date) -> String {
    guard let reset = resetTime else { return "--" }
    let remaining = reset.timeIntervalSince(now)
    guard remaining > 0 else { return "Abgelaufen" }
    let days = Int(remaining) / 86400
    let hours = (Int(remaining) % 86400) / 3600
    if days > 0 {
        return "\(days)d \(hours)h"
    }
    return "\(hours)h"
}

// MARK: - Usage pill section (left or right side)

private struct UsagePillSection: View {
    let icon: String
    let label: String
    let timeLeft: String
    let utilization: Double?
    let isLimited: Bool

    private var color: Color {
        if isLimited { return .red }
        return usageColor(for: utilization)
    }

    private var percentText: String {
        guard let util = utilization else { return "--%"  }
        return "\(min(Int(util * 100), 999))%"
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 1) {
                Text(percentText)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(color)

                Text(timeLeft)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

// MARK: - Main Floating Widget View

struct FloatingWidgetView: View {
    @EnvironmentObject var usageTracker: UsageWindowTracker

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let window = usageTracker.currentWindow {
            HStack(spacing: 10) {
                // Left: Session (5h window)
                UsagePillSection(
                    icon: "bolt.fill",
                    label: "Session",
                    timeLeft: formatSessionTimeLeft(resetTime: window.fiveHourResetTime, now: now),
                    utilization: window.fiveHourUtilization,
                    isLimited: window.isLimited
                )

                // Divider
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 1, height: 24)

                // Right: Weekly (7d window)
                UsagePillSection(
                    icon: "calendar",
                    label: "Woche",
                    timeLeft: formatWeeklyTimeLeft(resetTime: window.sevenDayResetTime, now: now),
                    utilization: window.sevenDayUtilization,
                    isLimited: window.sevenDayStatus == "exceeded_limit"
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.78))
                    .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)
            )
        } else {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                Text("Warte auf Daten...")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.78))
                    .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)
            )
        }
    }
}
