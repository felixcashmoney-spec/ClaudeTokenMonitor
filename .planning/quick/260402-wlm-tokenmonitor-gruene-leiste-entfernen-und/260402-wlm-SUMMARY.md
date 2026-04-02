---
phase: quick-260402-wlm
plan: 01
subsystem: ui, services
tags: [ui-cleanup, ram-optimization, webview, polling]
dependency_graph:
  requires: []
  provides: [CleanDashboard, LightweightAPIClient]
  affects: [DashboardView, ClaudeAPIClient, UsageWindowTracker, LogFileParser]
tech_stack:
  added: []
  patterns: [on-demand WKWebView lifecycle, deferred cleanup]
key_files:
  created: []
  modified:
    - ClaudeTokenMonitor/ClaudeTokenMonitor/Views/DashboardView.swift
    - ClaudeTokenMonitor/ClaudeTokenMonitor/Services/ClaudeAPIClient.swift
    - ClaudeTokenMonitor/ClaudeTokenMonitor/Services/UsageWindowTracker.swift
    - ClaudeTokenMonitor/ClaudeTokenMonitor/Services/LogFileParser.swift
decisions:
  - "Freshness threshold updated from 120s to 240s to account for 2x polling interval change"
  - "Next-update countdown in UsageLimitsCard corrected from 30s to 120s offset"
metrics:
  duration: ~8min
  completed: 2026-04-02
  tasks_completed: 2
  tasks_total: 3
  files_modified: 4
---

# Phase quick-260402-wlm Plan 01: Banner Removal and RAM Optimization Summary

**One-liner:** Removed green CurrentSessionBanner from dashboard and made WKWebView on-demand to reduce idle RAM from ~150-200MB to target ~40-60MB.

## What Was Built

### Task 1: Remove CurrentSessionBanner (commit f5f5f4c)

Deleted the `CurrentSessionBanner` struct entirely from `DashboardView.swift` (~80 lines removed), removed the `currentSession` computed property, removed the banner from the view body, and reduced the popover frame height from 520 to 460 points. The dashboard now shows only UsageLimitsCard, CreditsCard, TokenStatsSection, BudgetBanner, ProjectBreakdownSection, and the footer.

### Task 2: RAM Optimization (commit 4755229)

**ClaudeAPIClient.swift:** Removed the persistent `webView` property and `setupWebView()` from `init()`. Refactored `fetchAll()` to create a `WKWebView` locally, assign it to `activeWebView` for delegate callback routing, and release it via a `defer` block after the fetch completes. Updated `WKNavigationDelegate` methods to check `self.activeWebView` instead of `self.webView`.

**UsageWindowTracker.swift:** Increased `evaluate()` timer from 10s to 30s; increased API polling timer from 30s to 120s; updated API freshness threshold from 120s to 240s (2x polling interval for safety).

**LogFileParser.swift:** Increased polling timer from 10s to 30s.

**DashboardView.swift (additional):** Fixed the "Nächste Aktualisierung" countdown offset from 30s to 120s to match the new API polling interval.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing update] Updated apiDataFreshness threshold from 120s to 240s**
- **Found during:** Task 2
- **Issue:** The API freshness check `< 120` would immediately mark data as stale at the 120s mark, just as the new poll was firing. With the new 120s interval, the threshold needed to cover at least one full cycle.
- **Fix:** Changed all three `apiIsFresh` comparisons in `UsageWindowTracker` to `< 240`
- **Files modified:** `UsageWindowTracker.swift`
- **Commit:** 4755229

**2. [Rule 2 - Missing update] Fixed next-update countdown offset in UsageLimitsCard**
- **Found during:** Task 2
- **Issue:** `UsageLimitsCard` computed `nextUpdate = freshness.addingTimeInterval(30)` — this would show a countdown to a refresh that no longer happens at 30s.
- **Fix:** Changed offset to 120s to match new API polling interval
- **Files modified:** `DashboardView.swift`
- **Commit:** 4755229

## Pending Verification (Task 3 — checkpoint:human-verify)

The plan includes a manual verification step:
1. Build and run the app from Xcode
2. Confirm green "aktives Projekt" banner is gone from menubar popover
3. Confirm UsageLimitsCard and CreditsCard still display correctly
4. Check Activity Monitor for RAM — should be well under 100MB idle
5. Wait ~2 minutes and verify usage data still refreshes

## Known Stubs

None — all changes wire real behavior.

## Self-Check: PASSED

- f5f5f4c exists: FOUND
- 4755229 exists: FOUND
- DashboardView.swift modified: FOUND
- ClaudeAPIClient.swift modified: FOUND
- UsageWindowTracker.swift modified: FOUND
- LogFileParser.swift modified: FOUND
- No `CurrentSessionBanner` references remain in codebase
