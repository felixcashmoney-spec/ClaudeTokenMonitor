---
phase: quick-260327-ox0
plan: "01"
subsystem: session-tracking, dashboard
tags: [bug-fix, reset-time, project-discovery, cost-estimation, keyboard-shortcut]
dependency_graph:
  requires: []
  provides: [correct-reset-time, all-projects-visible, cost-estimate-display, keyboard-toggle]
  affects: [UsageWindowTracker, SessionWatcher, DashboardView, MenubarManager]
tech_stack:
  added: []
  patterns: [filesystem-validation, greedy-path-resolution, NSEvent-global-monitor]
key_files:
  created: []
  modified:
    - ClaudeTokenMonitor/ClaudeTokenMonitor/Models/TokenRecord.swift
    - ClaudeTokenMonitor/ClaudeTokenMonitor/Services/UsageWindowTracker.swift
    - ClaudeTokenMonitor/ClaudeTokenMonitor/Services/SessionWatcher.swift
    - ClaudeTokenMonitor/ClaudeTokenMonitor/Views/DashboardView.swift
    - ClaudeTokenMonitor/ClaudeTokenMonitor/MenubarManager.swift
decisions:
  - "Used greedy filesystem validation for project path resolution — at each dash-separated component, try slash-separator first, then dash-append, to correctly handle project names with dashes like 'ClaudeCode-skills-installieren'"
  - "nonisolated(unsafe) for NSEvent monitor references in MenubarManager.deinit — required for Swift 6 strict concurrency (deinit is nonisolated)"
  - "parseResetTime advances by 1 day if parsed time is in the past relative to the rate limit event, handling e.g. '4am' when the rate limit occurred at 11pm"
metrics:
  duration: "~3 minutes"
  completed: "2026-03-27T17:01:53Z"
  tasks_completed: 2
  files_modified: 5
---

# Quick Task 260327-ox0: Fix Reset Time Parsing and Project Discovery Summary

**One-liner:** Fixed reset-time parsing (rate limit message text -> actual time) and project path resolution (greedy filesystem validation for names with dashes), plus cost estimation display and Cmd+Shift+T shortcut.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Fix reset time parsing and project discovery bugs | a932661 | TokenRecord.swift, UsageWindowTracker.swift, SessionWatcher.swift |
| 2 | Add cost estimation and keyboard shortcut | 5d7cb65 | DashboardView.swift, MenubarManager.swift |

## Changes Made

### Task 1: Reset Time Parsing + Project Discovery

**TokenRecord.swift**
- Added `rateLimitResetMessage: String?` property (persisted via SwiftData) so the raw message is stored alongside the rate limit event.

**UsageWindowTracker.swift**
- Added `parseResetTime(from:relativeTo:) -> Date?` using `NSRegularExpression` to extract time (`4am`, `7pm`, `4:00am`, `16:00`) and timezone identifier (`Europe/Berlin`, `UTC`) from rate limit message text.
- Calculates the next occurrence of the parsed time using `Calendar` with the correct timezone; advances by 1 day if the time is already past the rate limit event.
- `evaluate()` now uses parsed reset time (falls back to `limitTime + 5h` only if parsing fails).

**SessionWatcher.swift**
- Passes `rateLimitResetMessage` through in both `pollForChanges` and `processSessionFile` when constructing `TokenRecord`.
- Replaced `deriveProjectPath` naive dash-replacement with `resolveProjectDirName` — a greedy filesystem validator that tries `/` as separator first, then `-` append, correctly disambiguating paths like `/Users/felixleis/ClaudeCode/skills installieren` from the encoded directory name `-Users-felixleis-ClaudeCode-skills-installieren`.
- Results cached in `[String: String]` dictionary to avoid repeated filesystem checks.

### Task 2: Cost Estimation + Keyboard Shortcut + Banner Polish

**DashboardView.swift**
- Added `totalCacheCreation` and `totalCacheRead` computed properties (splitting the existing `totalCache`).
- Added `estimatedCost: Double` using Claude Sonnet 4 pricing (Input $3/1M, Output $15/1M, Cache Write $3.75/1M, Cache Read $0.30/1M).
- Added cost row `"Geschaetzter API-Wert: $X.XX (Sonnet 4 Preise)"` below the stat cards.
- `CurrentSessionBanner` updated: pulsing green dot (opacity animation), green 3pt left border overlay, `.green.opacity(0.05)` background tint over `.ultraThinMaterial`.

**MenubarManager.swift**
- Added `setupKeyboardShortcut()` method with both `NSEvent.addGlobalMonitorForEvents` (background) and `addLocalMonitorForEvents` (foreground, returns nil to consume) for Cmd+Shift+T.
- Monitor references stored as `nonisolated(unsafe)` to comply with Swift 6 concurrency (deinit cleans them up).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Swift 6 deinit concurrency error on NSEvent monitor properties**
- **Found during:** Task 2 (first build attempt)
- **Issue:** `deinit` is nonisolated in Swift 6; couldn't access `@MainActor`-isolated `Any?` properties for cleanup.
- **Fix:** Marked `globalKeyMonitor` and `localKeyMonitor` as `nonisolated(unsafe)` — matches pattern already used in project for `static` formatters.
- **Files modified:** MenubarManager.swift
- **Commit:** 5d7cb65 (included in task commit)

## Self-Check
