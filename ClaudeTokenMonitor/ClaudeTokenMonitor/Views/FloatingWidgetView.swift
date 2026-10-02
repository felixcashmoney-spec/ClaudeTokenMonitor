import SwiftUI
import SQLite3

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

// MARK: - Floating Widget

struct FloatingWidgetView: View {
    @EnvironmentObject var usageTracker: UsageWindowTracker
    @EnvironmentObject var expandState: WidgetExpandState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            widgetContent(now: context.date)
                // Anchor the dynamic inner frame tightly to the physical top of the max NSPanel frame
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
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
            .frame(
                width: expandState.isExpanded ? 300 : 130,
                alignment: .top
            )
            .fixedSize(horizontal: false, vertical: true)
            .background(notchBg)
        } else {
            HStack(spacing: 5) {
                ProgressView().scaleEffect(0.4).frame(width: 8, height: 8)
                Text("Laden...")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(width: 130, height: 28)
            .background(notchBg)
        }
    }

    // MARK: - Compact Bar

    private func compactBar(w: UsageWindow, now: Date) -> some View {
        HStack(spacing: 8) {
            pill(icon: "bolt.fill",
                 util: w.fiveHourUtilization,
                 limited: w.isLimited)

            pill(icon: "calendar",
                 util: w.sevenDayUtilization,
                 limited: w.sevenDayStatus == "exceeded_limit")

            Image(systemName: expandState.isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(height: 28)
    }

    private func pill(icon: String, util: Double?, limited: Bool) -> some View {
        let color = limited ? Color.red : usageColor(for: util)
        let pct = util.map { "\(min(Int($0 * 100), 999))%" } ?? "--%"
        return HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(color)
            Text(pct)
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    // MARK: - Detail Panel (Dashboard-style)

    private func detailPanel(w: UsageWindow, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Subtle separator
            Rectangle()
                .fill(LinearGradient(
                    colors: [.clear, .white.opacity(0.08), .clear],
                    startPoint: .leading, endPoint: .trailing
                ))
                .frame(height: 0.5)

            // Section header
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
                Text("Nutzungslimits")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }

            VStack(alignment: .leading, spacing: 10) {
                ClaudeUsageCard(window: w, now: now)
                AntigravityUsageCard()
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Background

    private var notchBg: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 22,
            bottomTrailingRadius: 22,
            topTrailingRadius: 0
        )
        
        return Group {
            if expandState.isFullScreenBackground {
                shape.fill(.black)
            } else {
                shape.fill(.ultraThinMaterial)
            }
        }
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 6)
    }
}

struct ClaudeUsageCard: View {
    let window: UsageWindow?
    let now: Date
    @EnvironmentObject var usageTracker: UsageWindowTracker

    var body: some View {
        LiquidGlassCard(glowColor: .cyan) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(alignment: .lastTextBaseline) {
                    Image(systemName: "brain")
                        .font(.system(size: 12))
                        .foregroundStyle(.cyan)
                    Text("Claude Pro")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    if window != nil {
                        Text("Aktiv")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.15), in: Capsule())
                    }
                }
                
                // Ring and Stats
                HStack(spacing: 14) {
                    // Current Session (5h) Progress
                    UsageRingView(
                        percent: min(window?.fiveHourUtilization ?? 0, 1.0),
                        title: "Sitzung"
                    )
                    .frame(width: 64, height: 64)

                    // Weekly (7d) Progress
                    UsageRingView(
                        percent: min(window?.sevenDayUtilization ?? 0, 1.0),
                        title: "7 Tage"
                    )
                    .frame(width: 64, height: 64)

                    // Extra Credit Progress
                    if window?.extraUsageEnabled == true || window?.extraUsageMonthlyLimitCents ?? 0 > 0 {
                        let spent = window?.extraUsageSpentCents ?? 0
                        let balance = window?.creditBalanceCents ?? 0
                        let limitFromApi = window?.extraUsageMonthlyLimitCents ?? 0

                        let pct: Double = {
                            if limitFromApi > 0 {
                                return Double(spent) / Double(limitFromApi)
                            } else if spent + balance > 0 {
                                return Double(spent) / Double(spent + balance)
                            } else {
                                return 0
                            }
                        }()

                        let eurosSpent = Double(spent) / 100.0
                        let centerText = String(format: "%.2f €", eurosSpent).replacingOccurrences(of: ".", with: ",")

                        UsageRingView(
                            percent: min(pct, 1.0),
                            title: "Extra",
                            centerText: centerText
                        )
                        .frame(width: 64, height: 64)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                // Reset countdown section
                VStack(alignment: .leading, spacing: 6) {
                    Divider().overlay(Color.white.opacity(0.08))

                    Text("AUFFÜLLUNG")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)

                    if let reset5h = window?.fiveHourResetTime {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.cyan)
                            Text("Sitzung")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formatTimeLeft(reset5h, now: now))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                    }

                    if let reset7d = window?.sevenDayResetTime {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.system(size: 9))
                                .foregroundStyle(.cyan)
                            Text("Wöchentlich")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formatTimeLeft(reset7d, now: now))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                    }
                }

                // API status / Credit balance
                if let client = usageTracker.apiClient {
                    if client.needsLogin {
                        Button {
                            Task { await client.fetchAll() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "person.crop.circle.badge.exclamationmark")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.yellow)
                                Text("Bei claude.ai anmelden")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.yellow)
                            }
                        }
                        .buttonStyle(.plain)
                    } else if let error = client.lastError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.system(size: 8))
                                .foregroundStyle(.orange.opacity(0.8))
                                .lineLimit(1)
                        }
                    } else if let freshness = window?.apiDataFreshness {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.green.opacity(0.6))
                            Text("API \(freshness.formatted(.dateTime.hour().minute()))")
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                }

                // Prepaid credit balance
                if let balance = window?.creditBalanceCents, balance > 0 {
                    Divider().overlay(Color.white.opacity(0.08))
                    HStack {
                        Image(systemName: "creditcard.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.green)
                        Text("Guthaben")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2f €", Double(balance) / 100.0).replacingOccurrences(of: ".", with: ","))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                }

            }
        }
    }
}

private struct TokenStatRow: View {
    let title: String
    let value: Int
    let color: Color
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.5), radius: 3)
            
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(Double(value).formatted(.number.notation(.compactName)))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
    }
}

private struct UsageRingView: View {
    let percent: Double
    let title: String
    var centerText: String? = nil

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 8)

            Circle()
                .trim(from: 0, to: percent)
                .stroke(
                    AngularGradient(
                        colors: [.cyan, .blue, .purple, .cyan],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8, dampingFraction: 0.7), value: percent)

            VStack(spacing: 1) {
                if let centerText = centerText {
                    Text(centerText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                } else {
                    Text("\(Int(percent * 100))%")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Antigravity Credits Data (read from SQLite)

enum ProtobufField {
    case varint(Int)
    case bytes([UInt8])
    case float(Float)
}

func parseProtobufFields(_ data: [UInt8]) -> [(Int, ProtobufField)] {
    var fields: [(Int, ProtobufField)] = []
    var pos = 0
    while pos < data.count {
        let tag = data[pos]
        pos += 1
        let fn = Int(tag >> 3)
        let wt = Int(tag & 0x07)
        if wt == 0 {
            var val = 0
            var shift = 0
            while pos < data.count {
                let b = data[pos]
                pos += 1
                val |= Int(b & 0x7f) << shift
                shift += 7
                if (b & 0x80) == 0 { break }
            }
            fields.append((fn, .varint(val)))
        } else if wt == 2 {
            var len = 0
            var shift = 0
            while pos < data.count {
                let b = data[pos]
                pos += 1
                len |= Int(b & 0x7f) << shift
                shift += 7
                if (b & 0x80) == 0 { break }
            }
            if pos + len <= data.count {
                fields.append((fn, .bytes(Array(data[pos..<pos+len]))))
                pos += len
            } else { break }
        } else if wt == 5 {
            if pos + 4 <= data.count {
                let bytes = Array(data[pos..<pos+4])
                let floatVal = bytes.withUnsafeBytes { $0.load(as: Float.self) }
                fields.append((fn, .float(floatVal)))
                pos += 4
            } else { break }
        } else if wt == 1 { pos += 8 }
        else { break }
    }
    return fields
}
struct AntigravityModelQuota: Equatable, Identifiable {
    let id = UUID()
    let name: String
    let quotaID: Int
    let usageFraction: Double   // 0.0–1.0 from protobuf (missing = 0)
    let resetTimestamp: Date?   // real reset time from protobuf
    let totalSegments: Int = 5

    var usedSegments: Int {
        Int((usageFraction * Double(totalSegments)).rounded())
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name && lhs.quotaID == rhs.quotaID
            && lhs.usageFraction == rhs.usageFraction
            && lhs.resetTimestamp == rhs.resetTimestamp
    }
}

struct AntigravityCreditsData {
    let availableCredits: Int
    let minimumCreditsForUsage: Int
    let useAICredits: Bool
    let selectedModel: String?
    let models: [AntigravityModelQuota]
}

final class AntigravityDataService: ObservableObject, @unchecked Sendable {
    @Published var credits: AntigravityCreditsData?
    @Published var lastUpdated: Date?
    private var timer: Timer?
    private var fileMonitorSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    private static var dbPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Antigravity/User/globalStorage/state.vscdb").path
    }

    init() {
        loadFromDB()
        startFileMonitor()
        // Fallback poll every 15s in case file events are missed
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.loadFromDB()
            }
        }
    }

    deinit {
        stopFileMonitor()
    }

    /// Watch the SQLite DB file — re-read immediately on every write
    private func startFileMonitor() {
        let path = Self.dbPath
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename],
            queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.loadFromDB()
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        fileMonitorSource = source
    }

    private func stopFileMonitor() {
        fileMonitorSource?.cancel()
        fileMonitorSource = nil
        fileDescriptor = -1
    }

    func loadFromDB() {
        Task.detached(priority: .background) {
            let data = Self.readAntigravityState()
            await MainActor.run {
                self.credits = data
                self.lastUpdated = Date()
            }
        }
    }
    
    /// Read the Antigravity SQLite database for credits and model info
    private static func readAntigravityState() -> AntigravityCreditsData? {
        let dbPath = Self.dbPath
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }
        
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }
        
        let credits = readCreditsFromDB(db: db)
        let modelPref = readSelectedModelFromDB(db: db)
        let models = readModelsFromDB(db: db)
        
        return AntigravityCreditsData(
            availableCredits: credits.available,
            minimumCreditsForUsage: credits.minimum,
            useAICredits: credits.useAI,
            selectedModel: modelPref,
            models: models
        )
    }
    
    private static func readCreditsFromDB(db: OpaquePointer?) -> (available: Int, minimum: Int, useAI: Bool) {
        var available = 0
        var minimum = 0
        var useAI = false

        let query = "SELECT value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.modelCredits';"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return (available, minimum, useAI)
        }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            if let cStr = sqlite3_column_text(stmt, 0) {
                let base64Str = String(cString: cStr)
                if let rawData = Data(base64Encoded: base64Str) {
                    // Parse protobuf key-value pairs using robust parser
                    let outerFields = parseRawProtobuf([UInt8](rawData))
                    for of in outerFields where of.fn == 1 && of.wt == 2 {
                        guard let entryBytes = of.bytes else { continue }
                        let ef = parseRawProtobuf(entryBytes)
                        guard let keyBytes = ef.first(where: { $0.fn == 1 && $0.wt == 2 })?.bytes,
                              let key = String(bytes: keyBytes, encoding: .utf8) else { continue }
                        // field 2 = value wrapper → field 1 = base64 string
                        guard let valWrapper = ef.first(where: { $0.fn == 2 && $0.wt == 2 })?.bytes else { continue }
                        let vf = parseRawProtobuf(valWrapper)
                        guard let b64Bytes = vf.first(where: { $0.fn == 1 && $0.wt == 2 })?.bytes,
                              let b64Str = String(bytes: b64Bytes, encoding: .utf8),
                              let valueData = Data(base64Encoded: b64Str) else { continue }
                        // Decode varint value (skip field tag byte)
                        let varint = decodeProtobufVarint(valueData)
                        switch key {
                        case "availableCreditsSentinelKey":
                            available = varint ?? 0
                        case "minimumCreditAmountForUsageKey":
                            minimum = varint ?? 0
                        case "useAICreditsSentinelKey":
                            useAI = (varint ?? 0) != 0
                        default:
                            break
                        }
                    }
                }
            }
        }

        return (available, minimum, useAI)
    }
    
    private static func readSelectedModelFromDB(db: OpaquePointer?) -> String? {
        let query = "SELECT value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.modelPreferences';"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            if let cStr = sqlite3_column_text(stmt, 0) {
                let base64Str = String(cString: cStr)
                if let rawData = Data(base64Encoded: base64Str) {
                    let outerFields = parseRawProtobuf([UInt8](rawData))
                    for of in outerFields where of.fn == 1 && of.wt == 2 {
                        guard let entryBytes = of.bytes else { continue }
                        let ef = parseRawProtobuf(entryBytes)
                        guard let keyBytes = ef.first(where: { $0.fn == 1 && $0.wt == 2 })?.bytes,
                              String(bytes: keyBytes, encoding: .utf8) == "last_selected_agent_model_sentinel_key" else { continue }
                        guard let valWrapper = ef.first(where: { $0.fn == 2 && $0.wt == 2 })?.bytes else { continue }
                        let vf = parseRawProtobuf(valWrapper)
                        guard let b64Bytes = vf.first(where: { $0.fn == 1 && $0.wt == 2 })?.bytes,
                              let b64Str = String(bytes: b64Bytes, encoding: .utf8),
                              let valueData = Data(base64Encoded: b64Str) else { continue }
                        let modelId = decodeProtobufVarint(valueData)
                        return modelIdToName(modelId ?? 0)
                    }
                }
            }
        }
        return nil
    }

    private static func readModelsFromDB(db: OpaquePointer?) -> [AntigravityModelQuota] {
        let query = "SELECT value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.userStatus';"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let cStr = sqlite3_column_text(stmt, 0) else { return [] }

        let base64Str = String(cString: cStr)
        guard let outerData = Data(base64Encoded: base64Str) else { return [] }

        // Outer layer is a protobuf key-value wrapper; extract the inner base64 value
        // Use parseRawProtobuf (handles multi-byte varint lengths) instead of parseProtobufKeyValues
        var innerData: Data?
        let outerFields = parseRawProtobuf([UInt8](outerData))
        for of in outerFields where of.fn == 1 && of.wt == 2 {
            guard let entryBytes = of.bytes else { continue }
            let entryFields = parseRawProtobuf(entryBytes)
            guard let keyBytes = entryFields.first(where: { $0.fn == 1 && $0.wt == 2 })?.bytes,
                  String(bytes: keyBytes, encoding: .utf8) == "userStatusSentinelKey" else { continue }
            // field 2 = value wrapper → field 1 = base64 string
            if let valueWrapper = entryFields.first(where: { $0.fn == 2 && $0.wt == 2 })?.bytes {
                let valueFields = parseRawProtobuf(valueWrapper)
                if let b64Bytes = valueFields.first(where: { $0.fn == 1 && $0.wt == 2 })?.bytes,
                   let b64String = String(bytes: b64Bytes, encoding: .utf8),
                   let decoded = Data(base64Encoded: b64String) {
                    innerData = decoded
                }
            }
            break
        }
        guard let innerData else { return [] }

        // Parse top-level protobuf; field 33 holds the models container
        let topFields = parseRawProtobuf([UInt8](innerData))
        guard let modelsBlob = topFields.first(where: { $0.fn == 33 && $0.wt == 2 })?.bytes else { return [] }

        // Each sub-field 1 inside the container is one model entry
        let containerFields = parseRawProtobuf(modelsBlob)
        var models: [AntigravityModelQuota] = []

        for cf in containerFields where cf.fn == 1 && cf.wt == 2 {
            guard let entryBytes = cf.bytes else { continue }
            let ef = parseRawProtobuf(entryBytes)

            // field 1 (string) = model name
            guard let nameBytes = ef.first(where: { $0.fn == 1 && $0.wt == 2 })?.bytes,
                  let name = String(bytes: nameBytes, encoding: .utf8) else { continue }

            // field 2 (bytes) → sub varint = model ID
            var modelID = 0
            if let idBlob = ef.first(where: { $0.fn == 2 && $0.wt == 2 })?.bytes {
                let sub = parseRawProtobuf(idBlob)
                modelID = sub.first(where: { $0.wt == 0 })?.varint ?? 0
            }

            // field 15 (bytes) → quota info
            var usageFraction: Double = 0
            var resetDate: Date?
            if let quotaBlob = ef.first(where: { $0.fn == 15 && $0.wt == 2 })?.bytes {
                let qf = parseRawProtobuf(quotaBlob)
                // sub field 1, wire type 5 (float32) = usage 0.0–1.0
                if let f32 = qf.first(where: { $0.fn == 1 && $0.wt == 5 })?.float32 {
                    usageFraction = Double(f32)
                }
                // sub field 2 (bytes) → sub varint = reset Unix timestamp
                if let resetBlob = qf.first(where: { $0.fn == 2 && $0.wt == 2 })?.bytes {
                    let rf = parseRawProtobuf(resetBlob)
                    if let ts = rf.first(where: { $0.wt == 0 })?.varint, ts > 0 {
                        resetDate = Date(timeIntervalSince1970: TimeInterval(ts))
                    }
                }
            }

            models.append(AntigravityModelQuota(
                name: name,
                quotaID: modelID,
                usageFraction: usageFraction,
                resetTimestamp: resetDate
            ))
        }

        return models.sorted { $0.name > $1.name }
    }

    // MARK: - Low-level protobuf field parser

    private struct RawField {
        let fn: Int    // field number
        let wt: Int    // wire type
        let varint: Int?
        let bytes: [UInt8]?
        let float32: Float?
    }

    private static func parseRawProtobuf(_ data: [UInt8]) -> [RawField] {
        var results: [RawField] = []
        var pos = 0
        while pos < data.count {
            var tag = 0; var shift = 0
            while pos < data.count { let b = data[pos]; pos += 1; tag |= Int(b & 0x7f) << shift; shift += 7; if b & 0x80 == 0 { break } }
            let fn = tag >> 3; let wt = tag & 0x07
            switch wt {
            case 0: // varint
                var val = 0; shift = 0
                while pos < data.count { let b = data[pos]; pos += 1; val |= Int(b & 0x7f) << shift; shift += 7; if b & 0x80 == 0 { break } }
                results.append(RawField(fn: fn, wt: wt, varint: val, bytes: nil, float32: nil))
            case 2: // length-delimited
                var len = 0; shift = 0
                while pos < data.count { let b = data[pos]; pos += 1; len |= Int(b & 0x7f) << shift; shift += 7; if b & 0x80 == 0 { break } }
                guard pos + len <= data.count else { return results }
                results.append(RawField(fn: fn, wt: wt, varint: nil, bytes: Array(data[pos..<pos+len]), float32: nil))
                pos += len
            case 5: // 32-bit (float)
                guard pos + 4 <= data.count else { return results }
                let f = [data[pos], data[pos+1], data[pos+2], data[pos+3]].withUnsafeBytes { $0.load(as: Float.self) }
                results.append(RawField(fn: fn, wt: wt, varint: nil, bytes: nil, float32: f))
                pos += 4
            case 1: // 64-bit
                pos += 8
            default:
                return results
            }
        }
        return results
    }

    
    /// Parse the Antigravity protobuf key-value structure:
    /// Each entry is a length-delimited field 1 containing: field 1 (key string) + field 2 (base64 value string)
    private static func parseProtobufKeyValues(_ data: Data) -> [(String, String)] {
        var results: [(String, String)] = []
        var i = 0
        let bytes = [UInt8](data)
        
        while i < bytes.count {
            let tag = bytes[i]
            let fieldNum = tag >> 3
            let wireType = tag & 0x07
            i += 1
            
            guard fieldNum == 1, wireType == 2 else {
                // Skip unknown fields
                if wireType == 0 { // varint
                    while i < bytes.count && (bytes[i] & 0x80) != 0 { i += 1 }
                    if i < bytes.count { i += 1 }
                } else if wireType == 2 { // length-delimited, skip
                    if i < bytes.count {
                        let len = Int(bytes[i])
                        i += 1 + len
                    }
                }
                continue
            }
            
            // Read outer length
            guard i < bytes.count else { break }
            let outerLen = Int(bytes[i])
            i += 1
            guard i + outerLen <= bytes.count else { break }
            
            let innerData = Array(bytes[i..<(i + outerLen)])
            i += outerLen
            
            // Parse inner: field 1 = key, field 2 = value
            var key: String?
            var value: String?
            var j = 0
            while j < innerData.count {
                let innerTag = innerData[j]
                let innerField = innerTag >> 3
                let innerWire = innerTag & 0x07
                j += 1
                
                if innerWire == 2 {
                    guard j < innerData.count else { break }
                    let innerLen = Int(innerData[j])
                    j += 1
                    guard j + innerLen <= innerData.count else { break }
                    let content = Data(innerData[j..<(j + innerLen)])
                    j += innerLen
                    
                    if innerField == 1 {
                        key = String(data: content, encoding: .utf8)
                    } else if innerField == 2 {
                        // The value contains another length-delimited field: 0a 04 <base64>
                        // Parse inner-inner to get actual base64 string
                        if content.count > 2 && content[0] == 0x0a {
                            let valLen = Int(content[1])
                            if content.count >= 2 + valLen {
                                value = String(data: content.subdata(in: 2..<(2 + valLen)), encoding: .utf8)
                            }
                        }
                    }
                } else if innerWire == 0 {
                    // Skip varint
                    while j < innerData.count && (innerData[j] & 0x80) != 0 { j += 1 }
                    if j < innerData.count { j += 1 }
                }
            }
            
            if let key, let value {
                results.append((key, value))
            }
        }
        
        return results
    }
    
    /// Decode a protobuf varint from base64-decoded data (skipping field tag)
    private static func decodeProtobufVarint(_ data: Data) -> Int? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return nil }
        // Skip the field tag byte (e.g. 0x10 = field 2 varint, 0x08 = field 1 varint)
        var i = 1
        var value = 0
        var shift = 0
        while i < bytes.count {
            let b = Int(bytes[i])
            value |= (b & 0x7f) << shift
            shift += 7
            i += 1
            if (b & 0x80) == 0 { break }
        }
        return value
    }
    
    /// Map Antigravity model IDs to human-readable names
    private static func modelIdToName(_ id: Int) -> String {
        // These IDs are protobuf enum values from the Antigravity settings
        switch id {
        case 0: return "Default"
        case 1037: return "Claude Opus 4.6 (Thinking)"
        case 1101: return "Claude Sonnet 4.6 (Thinking)"
        default: return "Model \(id)"
        }
    }
}

struct AntigravityUsageCard: View {
    @StateObject private var service = AntigravityDataService()

    var body: some View {
        LiquidGlassCard(glowColor: .purple) {
            VStack(alignment: .leading, spacing: 12) {

                // Header
                HStack {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(.purple)
                    Text("Antigravity")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    if service.credits?.useAICredits == true {
                        Text("Credits aktiv")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.15), in: Capsule())
                    }
                }
                
                if let credits = service.credits {
                    // Credits info
                    VStack(alignment: .leading, spacing: 10) {
                        Text("AI CREDITS")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 12) {
                            // Credits ring
                            ZStack {
                                Circle()
                                    .stroke(Color.white.opacity(0.1), lineWidth: 6)
                                
                                let usedFraction: Double = {
                                    guard credits.availableCredits > 0 else { return 1.0 }
                                    // We don't know total, so show available as a gauge
                                    return max(0, min(1.0, Double(credits.availableCredits) / 1000.0))
                                }()
                                
                                Circle()
                                    .trim(from: 0, to: usedFraction)
                                    .stroke(
                                        AngularGradient(
                                            colors: [.purple, .pink, .purple],
                                            center: .center
                                        ),
                                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                                    )
                                    .rotationEffect(.degrees(-90))
                                    .animation(.spring(response: 0.8, dampingFraction: 0.7), value: usedFraction)

                                VStack(spacing: 1) {
                                    Text("\(credits.availableCredits)")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text("Credits")
                                        .font(.system(size: 7, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 52, height: 52)
                            
                            // Stats
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(.purple)
                                        .frame(width: 5, height: 5)
                                    Text("Verfügbar")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(credits.availableCredits)")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.white)
                                }
                                
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(.orange)
                                        .frame(width: 5, height: 5)
                                    Text("Min. für Nutzung")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(credits.minimumCreditsForUsage)")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.white)
                                }
                                
                                if let model = credits.selectedModel {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(.cyan)
                                            .frame(width: 5, height: 5)
                                        Text("Modell")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(model)
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.cyan)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Render the exact models list the user asked for
                    if !credits.models.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("MODEL QUOTA")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                            
                            ForEach(credits.models) { model in
                                AntigravityModelRow(model: model)
                            }
                        }
                    }
                } else {
                    // No data available
                    HStack {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.yellow)
                        Text("Keine Antigravity-Daten gefunden")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let updated = service.lastUpdated {
                    Text("Aktualisiert: \(updated.formatted(.dateTime.hour().minute()))")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
    }
}

struct AntigravityModelRow: View {
    let model: AntigravityModelQuota

    private func resetCountdown(now: Date) -> String {
        guard let reset = model.resetTimestamp else { return "" }
        let remaining = reset.timeIntervalSince(now)
        guard remaining > 0 else { return "Bereit" }
        let days = Int(remaining) / 86400
        let hours = (Int(remaining) % 86400) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if days > 0 { return "Reset in \(days)d \(hours)h" }
        if hours > 0 { return "Reset in \(hours)h \(minutes)m" }
        return "Reset in \(minutes)m"
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 4) {
                HStack(alignment: .lastTextBaseline) {
                    Text(model.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)

                    // Warning when quota is empty (no remaining)
                    if model.usageFraction == 0 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                    }

                    Spacer()

                    Text(resetCountdown(now: context.date))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                // 5-segment progress bar (segments = remaining quota)
                // Color gradient: white (full) → red (empty)
                HStack(spacing: 4) {
                    ForEach(0..<model.totalSegments, id: \.self) { i in
                        GeometryReader { geo in
                            let f = model.usageFraction
                            let segColor = Color(red: 1.0, green: f, blue: f)
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.1))

                                if i < model.usedSegments {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(
                                            LinearGradient(colors: [segColor, segColor.opacity(0.8)],
                                                           startPoint: .leading, endPoint: .trailing)
                                        )
                                        .frame(width: geo.size.width)
                                        .shadow(color: segColor.opacity(0.3), radius: 2)
                                }
                            }
                        }
                        .frame(height: 3)
                    }
                }
            }
        }
    }
}

struct LiquidGlassCard<Content: View>: View {
    var glowColor: Color? = nil
    var content: () -> Content
    
    init(glowColor: Color? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.glowColor = glowColor
        self.content = content
    }
    
    var body: some View {
        ZStack {
            // Optional Background Ambient Glow
            if let glowColor {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(glowColor)
                    .opacity(0.10)
                    .blur(radius: 12)
            }
            
            // Core Glass
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .environment(\.colorScheme, .dark)

            // Inner Highlight / Border for 3D effect
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.05), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )

            // Foreground Content
            content()
                .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
    }
}

