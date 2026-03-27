---
phase: quick-260327-pc1
plan: 01
subsystem: services/views
tags: [log-parsing, rate-limit, usage-tracking, dashboard, accuracy]
dependency_graph:
  requires: []
  provides: [LogFileParser, RateLimitInfo, WindowInfo, UsageWindow-7d, ExtraUsageBanner]
  affects: [DashboardView, UsageWindowTracker, MenubarManager]
tech_stack:
  added: [JSONSerialization, Combine-subscription, FileHandle-tail-read]
  patterns: [authoritative-data-preference, graceful-fallback, incremental-file-reading]
key_files:
  created:
    - ClaudeTokenMonitor/ClaudeTokenMonitor/Services/LogFileParser.swift
  modified:
    - ClaudeTokenMonitor/ClaudeTokenMonitor/Services/UsageWindowTracker.swift
    - ClaudeTokenMonitor/ClaudeTokenMonitor/Views/DashboardView.swift
    - ClaudeTokenMonitor/ClaudeTokenMonitor.xcodeproj/project.pbxproj
decisions:
  - LogFileParser owned internally by UsageWindowTracker (simpler wiring, no AppDelegate changes)
  - JSONSerialization used over Codable due to dynamic nested keys (5h, 7d window names)
  - "Authoritative data freshness threshold: 6 hours (covers one full rate limit window)"
  - "nonisolated(unsafe) removed from DateFormatter — DateFormatter is Sendable in this SDK"
  - "Token sums moved from session-level to TokenRecord-level for accurate time filtering"
metrics:
  duration: 25min
  completed: 2026-03-27
  tasks_completed: 2
  files_changed: 4
---

# Phase quick-260327-pc1 Plan 01: Major Accuracy Overhaul — Parse Claude Desktop Log Summary

**One-liner:** Authoritative rate limit tracking via ~/Library/Logs/Claude/claude.ai-web.log with exact 5h/7d window utilization, Unix-timestamp reset times, and extra usage status display.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Create LogFileParser and rewrite UsageWindowTracker | 3426185 | LogFileParser.swift (new), UsageWindowTracker.swift, project.pbxproj |
| 2 | Update DashboardView with 7d window and extra usage status | 65ebea6 | DashboardView.swift |

## What Was Built

### LogFileParser.swift (new)
- `@MainActor final class LogFileParser: ObservableObject`
- `@Published var latestInfo: RateLimitInfo?`
- Polls `~/Library/Logs/Claude/claude.ai-web.log` every 10s using incremental byte-offset reads
- Parses `[COMPLETION] Request failed Error:` lines, extracts JSON via JSONSerialization
- Decodes `5h` and `7d` window objects (`status`, `resets_at`, `utilization`, `surpassed_threshold`)
- Decodes `overageStatus`, `overageDisabledReason`, `overageInUse`
- Converts Unix timestamps to `Date` via `Date(timeIntervalSince1970:)`
- Parses log entry timestamps from `"yyyy-MM-dd HH:mm:ss"` prefix
- File-not-found handled gracefully (silently skips, `latestInfo` stays nil)

### UsageWindowTracker.swift (rewritten)
- `UsageWindow` struct expanded: `fiveHourUtilization`, `fiveHourResetTime`, `fiveHourStatus`, `sevenDayUtilization`, `sevenDayResetTime`, `sevenDayStatus`, `overageDisabledReason`, `overageInUse`
- Legacy fields preserved: `tokensUsed`, `learnedLimit`, `isLimited`, `remaining`, `usagePercent`
- Owns `LogFileParser` internally — no AppDelegate changes required
- Combine subscription (`$latestInfo`) triggers `evaluate()` on new log data
- `evaluate()` prefers authoritative log data when fresh (within 6h), falls back to token-based estimation
- All existing token-based logic preserved in `buildTokenWindow()`

### DashboardView.swift (updated)
- `PlanUsageBanner` redesigned with dual-window layout (5h + 7d bars stacked vertically)
- Each bar shows authoritative percentage (e.g., "83% genutzt") when log data available
- Exact reset times shown using `.time` style when limited
- Extra usage status banner: orange warning for `out_of_credits`, muted info for `org_level_disabled`, blue indicator for `overageInUse`
- Footer: "Basierend auf Claude Rate-Limit Daten" vs token-based fallback text
- `@Query private var allTokenRecords: [TokenRecord]` added for timestamp-accurate sums
- `filteredTokenRecords` replaces session-level filtering for `totalInput`, `totalOutput`, `totalCache`, `totalAll`, `estimatedCost`
- `monthlyTokens` uses `TokenRecord.timestamp` (not `session.lastActivityAt`)
- `projectBreakdown` groups by `record.session?.projectName` from token records

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] LogFileParser.swift not auto-discovered by Xcode project**
- **Found during:** Task 1 verification build
- **Issue:** Project uses explicit file references (PBXBuildFile/PBXFileReference sections), not auto-discovery. Build failed with "cannot find type 'LogFileParser' in scope"
- **Fix:** Added new entries to project.pbxproj: PBXBuildFile, PBXFileReference, Services group child, PBXSourcesBuildPhase entry
- **Files modified:** ClaudeTokenMonitor.xcodeproj/project.pbxproj
- **Commit:** 3426185

**2. [Rule 1 - Bug] nonisolated(unsafe) unnecessary on Sendable DateFormatter**
- **Found during:** Task 1 build (compiler warning)
- **Issue:** The pattern from SessionWatcher was copied but `DateFormatter` is `Sendable` in macOS 26 SDK, making `nonisolated(unsafe)` redundant
- **Fix:** Removed `nonisolated(unsafe)` from `logTimestampFormatter`
- **Files modified:** LogFileParser.swift
- **Commit:** 3426185

## Known Stubs

None — all data flows are wired. When `~/Library/Logs/Claude/claude.ai-web.log` is absent or has no `exceeded_limit` entries, the app gracefully shows the fallback "Noch kein Rate-Limit erkannt" message (same as before this plan).

## Self-Check: PASSED

- LogFileParser.swift: FOUND at ClaudeTokenMonitor/ClaudeTokenMonitor/Services/LogFileParser.swift
- UsageWindowTracker.swift: FOUND (modified)
- DashboardView.swift: FOUND (modified)
- Commit 3426185: FOUND
- Commit 65ebea6: FOUND
- Build: SUCCEEDED (xcodebuild returned "BUILD SUCCEEDED")
