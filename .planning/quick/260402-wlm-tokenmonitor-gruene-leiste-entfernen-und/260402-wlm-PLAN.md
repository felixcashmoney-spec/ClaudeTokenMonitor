---
phase: quick-260402-wlm
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - ClaudeTokenMonitor/ClaudeTokenMonitor/Views/DashboardView.swift
  - ClaudeTokenMonitor/ClaudeTokenMonitor/Services/ClaudeAPIClient.swift
  - ClaudeTokenMonitor/ClaudeTokenMonitor/Services/UsageWindowTracker.swift
  - ClaudeTokenMonitor/ClaudeTokenMonitor/Services/LogFileParser.swift
autonomous: false
requirements: [UI-cleanup, RAM-optimization]
must_haves:
  truths:
    - "The green CurrentSessionBanner with project name and token counts is no longer visible in the dashboard"
    - "UsageLimitsCard and CreditsCard still display and update correctly"
    - "App RAM usage is significantly reduced compared to before (target: under 100MB idle)"
  artifacts:
    - path: "ClaudeTokenMonitor/ClaudeTokenMonitor/Views/DashboardView.swift"
      provides: "Dashboard without CurrentSessionBanner"
    - path: "ClaudeTokenMonitor/ClaudeTokenMonitor/Services/ClaudeAPIClient.swift"
      provides: "Lightweight API client without persistent WKWebView"
  key_links:
    - from: "DashboardView.swift"
      to: "UsageWindowTracker"
      via: "EnvironmentObject"
      pattern: "@EnvironmentObject.*usageTracker"
---

<objective>
Remove the green "aktives Projekt" session banner from the dashboard and optimize the app's memory footprint.

Purpose: The user only wants to see remaining usage and credit balance — the green session banner with project name and token counts is unwanted clutter. Additionally, the app uses too much RAM, primarily due to the always-resident WKWebView in ClaudeAPIClient.

Output: Cleaner dashboard UI + reduced memory consumption.
</objective>

<execution_context>
@/Users/felixleis/.claude/get-shit-done/workflows/execute-plan.md
@/Users/felixleis/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@ClaudeTokenMonitor/ClaudeTokenMonitor/Views/DashboardView.swift
@ClaudeTokenMonitor/ClaudeTokenMonitor/Services/ClaudeAPIClient.swift
@ClaudeTokenMonitor/ClaudeTokenMonitor/Services/UsageWindowTracker.swift
@ClaudeTokenMonitor/ClaudeTokenMonitor/ClaudeTokenMonitorApp.swift
@ClaudeTokenMonitor/ClaudeTokenMonitor/MenubarManager.swift
</context>

<tasks>

<task type="auto">
  <name>Task 1: Remove CurrentSessionBanner and clean up DashboardView</name>
  <files>ClaudeTokenMonitor/ClaudeTokenMonitor/Views/DashboardView.swift</files>
  <action>
1. In DashboardView.body, remove the entire block that shows the CurrentSessionBanner:
   ```swift
   // Active session
   if let session = currentSession {
       CurrentSessionBanner(session: session)
   }
   ```

2. Remove the `currentSession` computed property from DashboardView (no longer needed):
   ```swift
   private var currentSession: Session? {
       sessions.sorted { ... }.first
   }
   ```

3. Delete the entire `CurrentSessionBanner` struct (lines ~248-324). It is no longer used anywhere.

4. Reduce the frame height from 520 to ~460 since there is less content:
   `.frame(width: 380, height: 460)`

5. Keep everything else intact: UsageLimitsCard, CreditsCard, TokenStatsSection, BudgetBanner, ProjectBreakdownSection, and the footer.
  </action>
  <verify>
    <automated>cd /Users/felixleis/ClaudeCode/ClaudeTokenMonitor && xcodebuild -scheme ClaudeTokenMonitor -destination 'platform=macOS' build 2>&1 | tail -5</automated>
  </verify>
  <done>Green CurrentSessionBanner no longer exists in the codebase. Dashboard still shows UsageLimitsCard, CreditsCard, and all other sections. App builds without errors.</done>
</task>

<task type="auto">
  <name>Task 2: Optimize RAM — lazy WKWebView and reduced polling</name>
  <files>ClaudeTokenMonitor/ClaudeTokenMonitor/Services/ClaudeAPIClient.swift, ClaudeTokenMonitor/ClaudeTokenMonitor/Services/UsageWindowTracker.swift, ClaudeTokenMonitor/ClaudeTokenMonitor/Services/LogFileParser.swift</files>
  <action>
The biggest RAM consumer is the always-resident WKWebView in ClaudeAPIClient (WebKit process typically uses 80-150MB). Optimize by creating the WKWebView on-demand and releasing it after each fetch cycle.

**ClaudeAPIClient.swift changes:**

1. Remove the `webView` instance property. Do NOT create a WKWebView in `init()`. Remove `setupWebView()` from init.

2. Refactor `fetchAll()` to create a temporary WKWebView, use it for the fetch, then release it:
   ```swift
   func fetchAll() async {
       let config = WKWebViewConfiguration()
       config.websiteDataStore = Self.dataStore
       let wv = WKWebView(frame: .zero, configuration: config)
       wv.navigationDelegate = self
       defer { wv.navigationDelegate = nil }

       // ... use wv instead of self.webView for all operations ...
       // Store wv in a temporary property so delegate callbacks can reference it
   }
   ```

3. Store the current active webView in an optional property `private var activeWebView: WKWebView?` that is set at the start of fetchAll and nilled out at the end (in a defer block). Update `loadAndWait` and delegate methods to use `activeWebView`.

4. Similarly for the login flow: the loginWebView is already created on-demand and cleaned up — keep that pattern.

**UsageWindowTracker.swift changes:**

5. Increase the API polling interval from 30 seconds to 120 seconds (2 minutes). The usage data from claude.ai does not change that frequently, and 30s polling keeps WKWebView processes hot:
   ```swift
   apiTimer = Timer.scheduledTimer(withTimeInterval: 120.0, repeats: true) { ... }
   ```

6. Increase the main evaluate() timer from 10 seconds to 30 seconds:
   ```swift
   timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { ... }
   ```

**LogFileParser.swift changes:**

7. Increase the polling interval from 10 seconds to 30 seconds — log files do not change that fast.

These changes together should reduce idle RAM from ~150-200MB to ~40-60MB by not keeping a WebKit process alive between fetches.
  </action>
  <verify>
    <automated>cd /Users/felixleis/ClaudeCode/ClaudeTokenMonitor && xcodebuild -scheme ClaudeTokenMonitor -destination 'platform=macOS' build 2>&1 | tail -5</automated>
  </verify>
  <done>WKWebView is created on-demand during fetchAll() and released after. Polling intervals increased to 120s (API), 30s (evaluate), 30s (log parser). App builds without errors. Memory should be significantly lower at idle.</done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 3: Verify UI cleanup and RAM improvement</name>
  <action>User verifies the visual changes and memory improvement.</action>
  <what-built>Removed green session banner and optimized RAM usage by making WKWebView on-demand and reducing polling frequency.</what-built>
  <how-to-verify>
    1. Build and run the app from Xcode
    2. Open the menubar popover — verify the green banner with "aktives Projekt" and token counts is gone
    3. Verify that UsageLimitsCard (5h/7d utilization bars) and CreditsCard (Guthaben) still display correctly
    4. Check Activity Monitor for the app's memory usage — should be well under 100MB when idle (previously 150-200MB)
    5. Wait ~2 minutes and verify the usage data still refreshes (check "Naechste Aktualisierung" countdown in the limits card)
  </how-to-verify>
  <resume-signal>Type "approved" or describe issues</resume-signal>
</task>

</tasks>

<verification>
- App builds successfully with `xcodebuild`
- No references to `CurrentSessionBanner` remain in the codebase
- WKWebView is not retained as a permanent instance property
- Polling intervals are 120s (API), 30s (evaluate/log)
</verification>

<success_criteria>
- Green session banner completely removed from UI
- Usage limits and credit balance continue to display and auto-refresh
- App idle RAM under 100MB (vs previous 150-200MB)
</success_criteria>

<output>
After completion, create `.planning/quick/260402-wlm-tokenmonitor-gruene-leiste-entfernen-und/260402-wlm-SUMMARY.md`
</output>
