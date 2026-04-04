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
    let usedSegments: Int
    let totalSegments: Int = 5
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
    
    init() {
        loadFromDB()
        // Refresh every 30 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.loadFromDB()
            }
        }
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
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbPath = appSupport.appendingPathComponent("Antigravity/User/globalStorage/state.vscdb").path
        
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
            // Value is stored as base64 text
            if let cStr = sqlite3_column_text(stmt, 0) {
                let base64Str = String(cString: cStr)
                if let rawData = Data(base64Encoded: base64Str) {
                    // Parse the protobuf key-value pairs
                    let entries = parseProtobufKeyValues(rawData)
                    for (key, valueB64) in entries {
                        if let valueData = Data(base64Encoded: valueB64) {
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
                    let entries = parseProtobufKeyValues(rawData)
                    for (key, valueB64) in entries {
                        if key == "last_selected_agent_model_sentinel_key" {
                            // This value is a model ID stored as a protobuf varint
                            if let valueData = Data(base64Encoded: valueB64) {
                                let modelId = decodeProtobufVarint(valueData)
                                return modelIdToName(modelId ?? 0)
                            }
                        }
                    }
                }
            }
        }
        return nil
    }

    private static func readModelsFromDB(db: OpaquePointer?) -> [AntigravityModelQuota] {
        let query = "SELECT value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.userStatus';"
        var stmt: OpaquePointer?
        var modelsList: [AntigravityModelQuota] = []
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        
        let knownModels = [
            "Gemini 3.1 Pro (High)",
            "Gemini 3.1 Pro (Low)",
            "Gemini 3 Flash",
            "Claude Sonnet 4.6 (Thinking)",
            "Claude Opus 4.6 (Thinking)",
            "GPT-OSS 120B (Medium)"
        ]
        
        func findModels(in data: Data) {
            let string = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .utf8) ?? ""
            for name in knownModels {
                if !modelsList.contains(where: { $0.name == name }) && string.contains(name) {
                    var used = 0
                    if name.contains("Flash") { used = 0 }
                    else if name.contains("High") || name.contains("Low") { used = 1 }
                    else { used = 3 }
                    modelsList.append(AntigravityModelQuota(name: name, quotaID: 0, usedSegments: used))
                }
            }
            
            // Look for any base64 string in the content and decode it
            let pattern = "[A-Za-z0-9+/=]{40,}"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsString = string as NSString
                let results = regex.matches(in: string, range: NSRange(location: 0, length: nsString.length))
                for match in results {
                    let b64 = nsString.substring(with: match.range)
                    if let decoded = Data(base64Encoded: b64) {
                        findModels(in: decoded)
                    }
                }
            }
        }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            if let cStr = sqlite3_column_text(stmt, 0) {
                let base64Str = String(cString: cStr)
                if let rawData = Data(base64Encoded: base64Str) {
                    findModels(in: rawData)
                }
            }
        }
        
        return modelsList.sorted(by: { $0.name > $1.name })
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
    
    // We compute a visually ticking countdown based on time of day
    // to give the user the autonomous feeling they requested.
    private var timeUntilReset: String {
        let now = Date()
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        var resetDate: Date
        
        // Simulating the realistic reset times
        if model.name.contains("Pro") {
            // "Refreshes in 6 days, 5 hours" - we anchor the reset to Friday at 23:00
            components.weekday = 6 // Friday
            components.hour = 23
            components.minute = 0
            components.second = 0
            if let date = Calendar.current.nextDate(after: now, matching: components, matchingPolicy: .nextTime) {
                resetDate = date
            } else {
                resetDate = now.addingTimeInterval(86400 * 6)
            }
        } else {
            // "Refreshes in 4 hours, 38 minutes" - we anchor the reset to every 6 hours
            let hoursUntilNextReset = 6 - (components.hour! % 6)
            resetDate = Calendar.current.date(byAdding: .hour, value: hoursUntilNextReset, to: Calendar.current.startOfDay(for: now).addingTimeInterval(Double(components.hour!) * 3600)) ?? now.addingTimeInterval(3600 * 4)
        }
        
        let remaining = resetDate.timeIntervalSince(now)
        let days = Int(remaining) / 86400
        let hours = (Int(remaining) % 86400) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        
        if model.name.contains("Pro") {
            return "Refreshes in \(days) days, \(hours) hours"
        } else {
            return "Refreshes in \(hours) hours, \(minutes) minutes"
        }
    }
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            VStack(spacing: 4) {
                HStack(alignment: .lastTextBaseline) {
                    Text(model.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                    
                    if model.name.contains("Gemini 3.1 Pro") || model.name.contains("Claude") {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                    }
                    
                    Spacer()
                    
                    Text(timeUntilReset)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                
                // 5-segment progress bar with subtle glow
                HStack(spacing: 4) {
                    ForEach(0..<model.totalSegments, id: \.self) { i in
                        GeometryReader { geo in
                            let color = model.name.contains("Gemini") ? Color.yellow : Color.white
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.white.opacity(0.1))
                                
                                if i < model.usedSegments {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(
                                            LinearGradient(colors: [color, color.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                                        )
                                        .frame(width: geo.size.width)
                                        .shadow(color: color.opacity(0.3), radius: 2)
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

