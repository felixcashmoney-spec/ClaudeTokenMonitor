---
phase: quick-260327-qfx
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - ClaudeTokenMonitor/ClaudeTokenMonitor/Services/ClaudeAPIClient.swift
  - ClaudeTokenMonitor/ClaudeTokenMonitor/Services/UsageWindowTracker.swift
  - ClaudeTokenMonitor/ClaudeTokenMonitor/Views/DashboardView.swift
  - ClaudeTokenMonitor/ClaudeTokenMonitor/ClaudeTokenMonitorApp.swift
  - ClaudeTokenMonitor/ClaudeTokenMonitor.xcodeproj/project.pbxproj
autonomous: true
requirements: [QUICK-QFX]
must_haves:
  truths:
    - "Dashboard shows live 5h and 7d utilization percentages from the claude.ai API"
    - "Dashboard shows credit balance in EUR and extra usage spending in EUR"
    - "Data refreshes automatically every 60 seconds"
    - "App falls back gracefully to log-based data when API is unavailable"
  artifacts:
    - path: "ClaudeTokenMonitor/ClaudeTokenMonitor/Services/ClaudeAPIClient.swift"
      provides: "Cookie decryption, API calls, response models"
      min_lines: 150
    - path: "ClaudeTokenMonitor/ClaudeTokenMonitor/Services/UsageWindowTracker.swift"
      provides: "Merged API + log data evaluation"
    - path: "ClaudeTokenMonitor/ClaudeTokenMonitor/Views/DashboardView.swift"
      provides: "Credit balance and spending display in EUR"
  key_links:
    - from: "ClaudeAPIClient.swift"
      to: "Claude Desktop Cookies SQLite + Keychain"
      via: "SQLite3 C API + Security framework"
      pattern: "SecItemCopyMatching|sqlite3_open"
    - from: "UsageWindowTracker.swift"
      to: "ClaudeAPIClient.swift"
      via: "apiClient.fetchUsage() called on 60s timer"
      pattern: "apiClient.*fetch"
    - from: "DashboardView.swift"
      to: "UsageWindow"
      via: "usageTracker.currentWindow properties for credit/spending"
      pattern: "creditBalance|extraUsageSpent"
---

<objective>
Add a ClaudeAPIClient service that reads session cookies from the Claude Desktop app's encrypted cookie store (SQLite + Keychain), calls the claude.ai usage and billing API endpoints, and displays live credit balance and extra usage spending in the dashboard.

Purpose: Replace estimated/log-based usage data with authoritative live data from the claude.ai API, giving the user real-time visibility into their credit balance and spending.
Output: ClaudeAPIClient.swift service, enhanced UsageWindowTracker, updated DashboardView with EUR credit display.
</objective>

<execution_context>
@/Users/felixleis/.claude/get-shit-done/workflows/execute-plan.md
@/Users/felixleis/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@ClaudeTokenMonitor/ClaudeTokenMonitor/Services/UsageWindowTracker.swift
@ClaudeTokenMonitor/ClaudeTokenMonitor/Services/LogFileParser.swift
@ClaudeTokenMonitor/ClaudeTokenMonitor/Views/DashboardView.swift
@ClaudeTokenMonitor/ClaudeTokenMonitor/ClaudeTokenMonitorApp.swift

<interfaces>
<!-- Existing types the executor needs -->

From UsageWindowTracker.swift:
```swift
struct UsageWindow {
    let fiveHourUtilization: Double?
    let fiveHourResetTime: Date?
    let fiveHourStatus: String?
    let sevenDayUtilization: Double?
    let sevenDayResetTime: Date?
    let sevenDayStatus: String?
    let overageDisabledReason: String?
    let overageInUse: Bool
    let tokensUsed: Int
    let learnedLimit: Int?
    let isLimited: Bool
}

@MainActor
final class UsageWindowTracker: ObservableObject {
    @Published var currentWindow: UsageWindow?
    func start(modelContext: ModelContext)
    func stop()
    func evaluate()
}
```

From ClaudeTokenMonitorApp.swift:
```swift
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    // Services are created here and wired together
    private var usageTracker: UsageWindowTracker?
}
```
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create ClaudeAPIClient with cookie decryption and API calls</name>
  <files>ClaudeTokenMonitor/ClaudeTokenMonitor/Services/ClaudeAPIClient.swift</files>
  <action>
Create a new `ClaudeAPIClient` class that:

1. **Cookie Decryption (Chromium Safe Storage format):**
   - Read the Claude Desktop cookie SQLite DB at `~/Library/Application Support/Claude/Cookies`
   - Use the SQLite3 C API (`import SQLite3`) to query: `SELECT name, encrypted_value, host_key FROM cookies WHERE host_key LIKE '%claude.ai%'`
   - For each encrypted cookie value:
     - Strip the first 3 bytes ("v10" prefix)
     - Read the Keychain password: use `SecItemCopyMatching` with service name "Claude Safe Storage" — this returns the base64-encoded password string
     - Derive AES key: `PBKDF2(password, salt: "saltysalt", iterations: 1003, keyLen: 16)` using `CCKeyDerivationPBKDF` from `import CommonCrypto`
     - Decrypt: AES-128-CBC with IV = 16 bytes of 0x20 (space character, i.e. `[UInt8](repeating: 0x20, count: 16)`)
     - Use `CCCrypt` with `kCCDecrypt`, `kCCAlgorithmAES128`, `kCCOptionPKCS7Padding`
   - Extract these cookies: `sessionKey` (the auth cookie), `cf_clearance`, `lastActiveOrg` (for orgId — this one may NOT be encrypted, check both encrypted_value and value columns)
   - Cache decrypted cookies for reuse (invalidate every 5 minutes in case they rotate)

2. **API Response Models (Codable structs):**
   ```swift
   struct UsageResponse: Codable {
       let five_hour: WindowResponse
       let seven_day: WindowResponse
       let extra_usage: ExtraUsageResponse
   }
   struct WindowResponse: Codable {
       let utilization: Int  // 0-100 integer
       let resets_at: String // ISO 8601 date
   }
   struct ExtraUsageResponse: Codable {
       let is_enabled: Bool
       let used_credits: Int // cents
       let monthly_limit: Int? // cents
   }
   struct PrepaidCreditsResponse: Codable {
       let amount: Int // cents
       let currency: String
       let auto_reload_settings: AutoReloadSettings?
   }
   struct AutoReloadSettings: Codable {
       // optional fields, include if discoverable
   }
   struct OverageSpendResponse: Codable {
       let is_enabled: Bool
       let monthly_credit_limit: Int? // cents
       let currency: String?
       let used_credits: Int // cents
       let disabled_reason: String?
       let out_of_credits: Bool?
   }
   ```

3. **API Calls:**
   - Base URL: `https://claude.ai`
   - All requests need headers: `Cookie: sessionKey={val}; cf_clearance={val}`, `Content-Type: application/json`, `User-Agent: Mozilla/5.0` (to avoid bot detection)
   - `fetchUsage(orgId:)` → GET `/api/organizations/{orgId}/usage` → returns `UsageResponse`
   - `fetchPrepaidCredits(orgId:)` → GET `/api/organizations/{orgId}/prepaid/credits` → returns `PrepaidCreditsResponse`
   - `fetchOverageSpend(orgId:)` → GET `/api/organizations/{orgId}/overage_spend_limit` → returns `OverageSpendResponse`
   - All calls use `URLSession.shared` with `async/await`
   - Handle HTTP errors gracefully: log to console, return nil
   - Add a convenience `fetchAll()` method that calls all three endpoints and returns a combined result struct:
     ```swift
     struct ClaudeAPIData {
         let usage: UsageResponse?
         let prepaidCredits: PrepaidCreditsResponse?
         let overage: OverageSpendResponse?
         let fetchedAt: Date
     }
     ```

4. **Error handling:** All errors (Keychain access denied, cookie DB locked, network errors) should be caught and logged via `print()` — never crash. Return nil for failed fetches. The class should be `@MainActor` and expose a `@Published var latestData: ClaudeAPIData?`.

5. **Entitlements note:** The app needs `com.apple.security.network.client` for outgoing HTTPS. Also needs no sandbox for Keychain/filesystem access to Claude's cookie DB (the app is already not sandboxed based on existing filesystem access patterns).

IMPORTANT: The `lastActiveOrg` cookie value IS the orgId string (UUID format). It may be stored unencrypted in the `value` column rather than `encrypted_value`. Check the `value` column first; if empty/null, try decrypting `encrypted_value`.
  </action>
  <verify>
    <automated>cd /Users/felixleis/ClaudeCode/ClaudeTokenMonitor && xcodebuild -scheme ClaudeTokenMonitor -destination 'platform=macOS' build 2>&1 | tail -20</automated>
  </verify>
  <done>ClaudeAPIClient.swift compiles, contains cookie decryption via CommonCrypto + Security framework, three API endpoint methods, and a combined fetchAll() method. Response models are Codable. All errors are caught gracefully.</done>
</task>

<task type="auto">
  <name>Task 2: Enhance UsageWindowTracker to consume API data and update DashboardView</name>
  <files>
    ClaudeTokenMonitor/ClaudeTokenMonitor/Services/UsageWindowTracker.swift,
    ClaudeTokenMonitor/ClaudeTokenMonitor/Views/DashboardView.swift,
    ClaudeTokenMonitor/ClaudeTokenMonitor/ClaudeTokenMonitorApp.swift
  </files>
  <action>
**A. Extend UsageWindow struct** (in UsageWindowTracker.swift):
Add these new fields to `UsageWindow`:
```swift
// API-sourced credit data
let creditBalanceCents: Int?        // prepaid credits in cents
let creditCurrency: String?         // "EUR"
let extraUsageSpentCents: Int?      // extra usage used_credits in cents
let extraUsageMonthlyLimitCents: Int? // monthly limit in cents
let extraUsageEnabled: Bool?        // is extra usage enabled
let apiDataFreshness: Date?         // when API data was last fetched
```
Update ALL existing `UsageWindow(...)` initializer call sites to include the new fields (pass `nil` for all new fields at existing call sites).

**B. Integrate ClaudeAPIClient into UsageWindowTracker:**
- Add a `private var apiClient: ClaudeAPIClient?` property
- Add a `private var apiTimer: Timer?` for the 60-second API polling (separate from the existing 10s log timer)
- In `start(modelContext:)`: create `ClaudeAPIClient()`, assign to `apiClient`, start apiTimer with 60s interval that calls `apiClient.fetchAll()` then `evaluate()`
- In `stop()`: invalidate apiTimer, nil out apiClient
- In `evaluate()`: read `apiClient?.latestData` and merge into the UsageWindow:
  - If API data exists AND is fresh (< 120s old): prefer API utilization values over log-based ones
  - API `five_hour.utilization` is 0-100 integer — divide by 100.0 for the Double field
  - API `five_hour.resets_at` is ISO 8601 string — parse with `ISO8601DateFormatter`
  - Always populate creditBalanceCents, extraUsageSpentCents etc. from API data
  - If API unavailable: fall back to existing log-based evaluation (no regression)

**C. Update DashboardView** to show credit/spending data:
- In `PlanUsageBanner`, add a new section AFTER the existing extra usage banner:

```swift
// Credit & Spending section (only shown when API data available)
if let balance = window.creditBalanceCents {
    Divider()
    VStack(alignment: .leading, spacing: 6) {
        HStack {
            Image(systemName: "eurosign.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Guthaben & Ausgaben")
                .font(.caption.weight(.semibold))
        }

        HStack {
            Text("Prepaid-Guthaben:")
                .font(.caption2)
            Spacer()
            Text(formatEUR(cents: balance))
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.green)
        }

        if let spent = window.extraUsageSpentCents, window.extraUsageEnabled == true {
            HStack {
                Text("Extra Usage ausgegeben:")
                    .font(.caption2)
                Spacer()
                Text(formatEUR(cents: spent))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(spent > 0 ? .orange : .secondary)
            }
            if let limit = window.extraUsageMonthlyLimitCents {
                HStack {
                    Text("Monatliches Limit:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatEUR(cents: limit))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }

        if let freshness = window.apiDataFreshness {
            Text("Aktualisiert: \(freshness, style: .relative) zurueck")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }
}
```

- Add a `formatEUR(cents:)` helper function in the view file:
```swift
private func formatEUR(cents: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "EUR"
    formatter.locale = Locale(identifier: "de_DE")
    return formatter.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "\(Double(cents) / 100.0) EUR"
}
```

IMPORTANT: All amounts from API are in CENTS — divide by 100 for display. Use German locale for currency formatting ("8,15 EUR" style).

**D. Wire ClaudeAPIClient in AppDelegate** (ClaudeTokenMonitorApp.swift):
No changes needed — ClaudeAPIClient is created internally by UsageWindowTracker (encapsulated, same pattern as LogFileParser).
  </action>
  <verify>
    <automated>cd /Users/felixleis/ClaudeCode/ClaudeTokenMonitor && xcodebuild -scheme ClaudeTokenMonitor -destination 'platform=macOS' build 2>&1 | tail -20</automated>
  </verify>
  <done>UsageWindow has credit/spending fields. UsageWindowTracker polls API every 60s and merges data. DashboardView shows credit balance in EUR, extra usage spending in EUR with German locale formatting. App compiles and runs. Falls back gracefully when API is unavailable.</done>
</task>

</tasks>

<verification>
1. App compiles without errors: `xcodebuild build` succeeds
2. ClaudeAPIClient.swift exists with cookie decryption logic (CommonCrypto + Security framework)
3. UsageWindow struct has creditBalanceCents, extraUsageSpentCents fields
4. DashboardView displays EUR amounts with German locale formatting
5. API polling runs on 60s interval (separate from 10s log polling)
6. When API is unavailable, existing log-based data continues to work
</verification>

<success_criteria>
- ClaudeAPIClient reads encrypted cookies from Claude Desktop's SQLite DB using Keychain + CommonCrypto
- Three API endpoints are called: usage, prepaid/credits, overage_spend_limit
- Dashboard shows prepaid credit balance in EUR (e.g., "8,15 EUR")
- Dashboard shows extra usage spending in EUR when enabled
- 60-second polling interval for API data
- Graceful fallback to log-based data when API fails
- All amounts correctly divided by 100 (cents to EUR)
</success_criteria>

<output>
After completion, create `.planning/quick/260327-qfx-add-claudeapiclient-service-for-live-usa/260327-qfx-SUMMARY.md`
</output>
