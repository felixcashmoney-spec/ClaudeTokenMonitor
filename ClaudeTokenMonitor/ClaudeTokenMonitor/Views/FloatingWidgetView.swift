import SwiftUI

// MARK: - Helpers

private func usageColor(for utilization: Double?) -> Color {
    guard let util = utilization else { return .gray }
    if util >= 0.95 { return .red }
    if util >= 0.80 { return .orange }
    if util >= 0.50 { return .yellow }
    return .green
}

private func formatTimeLeft(_ resetTime: Date?, now: Date) -> String {
    guard let reset = resetTime else { return "--" }
    let remaining = reset.timeIntervalSince(now)
    guard remaining > 0 else { return "0m" }
    let days = Int(remaining) / 86400
    let hours = (Int(remaining) % 86400) / 3600
    let minutes = (Int(remaining) % 3600) / 60
    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
}

private func formatEUR(cents: Int) -> String {
    String(format: "%.2f €", Double(cents) / 100.0)
}

// MARK: - Floating Widget

struct FloatingWidgetView: View {
    @EnvironmentObject var usageTracker: UsageWindowTracker
    @EnvironmentObject var expandState: WidgetExpandState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            widgetContent(now: context.date)
        }
        .frame(width: 300)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func widgetContent(now: Date) -> some View {
        if let w = usageTracker.currentWindow {
            VStack(spacing: 0) {
                compactBar(w: w, now: now)
                    .contentShape(Rectangle())
                    .onTapGesture { expandState.toggle() }

                if expandState.isExpanded {
                    detailPanel(w: w, now: now)
                }
            }
            .frame(width: 300, height: expandState.isExpanded ? 250 : 44, alignment: .top)
            .clipped()
            .background(notchBg)
        } else {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.45).frame(width: 10, height: 10)
                Text("Laden...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(width: 300, height: 44)
            .background(notchBg)
        }
    }

    // MARK: - Compact Bar

    private func compactBar(w: UsageWindow, now: Date) -> some View {
        HStack(spacing: 14) {
            pill(icon: "bolt.fill",
                 util: w.fiveHourUtilization,
                 limited: w.isLimited,
                 time: formatTimeLeft(w.fiveHourResetTime, now: now))

            pill(icon: "calendar",
                 util: w.sevenDayUtilization,
                 limited: w.sevenDayStatus == "exceeded_limit",
                 time: formatTimeLeft(w.sevenDayResetTime, now: now))

            // Chevron
            Image(systemName: expandState.isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(width: 300, height: 44)
    }

    private func pill(icon: String, util: Double?, limited: Bool, time: String) -> some View {
        let color = limited ? Color.red : usageColor(for: util)
        let pct = util.map { "\(min(Int($0 * 100), 999))%" } ?? "--%"
        return HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
            Text(pct)
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
            Text(time)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Detail Panel

    private func detailPanel(w: UsageWindow, now: Date) -> some View {
        VStack(spacing: 10) {
            Divider().overlay(Color.white.opacity(0.1))

            progressRow(
                label: "Sitzung (5h)",
                icon: "bolt.fill",
                util: w.fiveHourUtilization,
                limited: w.isLimited,
                reset: w.fiveHourResetTime, now: now
            )

            progressRow(
                label: "Woche (7d)",
                icon: "calendar",
                util: w.sevenDayUtilization,
                limited: w.sevenDayStatus == "exceeded_limit",
                reset: w.sevenDayResetTime, now: now
            )

            if let balance = w.creditBalanceCents {
                Divider().overlay(Color.white.opacity(0.1))
                HStack {
                    Text("Guthaben")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text(formatEUR(cents: balance))
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(balance > 0 ? .green : .red)
                }
                if let spent = w.extraUsageSpentCents, w.extraUsageEnabled == true {
                    HStack {
                        Text("Ausgegeben")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Text(formatEUR(cents: spent))
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(spent > 0 ? .orange : .white.opacity(0.4))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .transition(.opacity)
    }

    private func progressRow(label: String, icon: String, util: Double?, limited: Bool, reset: Date?, now: Date) -> some View {
        let color = limited ? Color.red : usageColor(for: util)
        let pct = util ?? 0

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("\(Int(pct * 100))%")
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * min(pct, 1.0))
                }
            }
            .frame(height: 4)

            if let r = reset {
                Text("Reset in \(formatTimeLeft(r, now: now))")
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    // MARK: - Background

    private var notchBg: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 22,
            bottomTrailingRadius: 22,
            topTrailingRadius: 0
        )
        .fill(Color.black)
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}
