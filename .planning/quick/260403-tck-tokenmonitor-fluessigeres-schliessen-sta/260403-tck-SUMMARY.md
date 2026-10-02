---
phase: quick-260403-tck
plan: "01"
subsystem: app-lifecycle, floating-widget
tags: [quit, animation, positioning, build-tooling]
dependency_graph:
  requires: [quick-260402-x3o]
  provides: [smooth-quit, safe-widget-position, standalone-build]
  affects: [ClaudeTokenMonitorApp, FloatingWidgetWindow, MenubarManager]
tech_stack:
  added: []
  patterns: [NSAnimationContext fade-out, visibleFrame clamping, notification-driven quit]
key_files:
  created:
    - ClaudeTokenMonitor/build.sh
    - ClaudeTokenMonitor/.gitignore
  modified:
    - ClaudeTokenMonitor/ClaudeTokenMonitor/ClaudeTokenMonitorApp.swift
    - ClaudeTokenMonitor/ClaudeTokenMonitor/FloatingWidgetWindow.swift
    - ClaudeTokenMonitor/ClaudeTokenMonitor/MenubarManager.swift
decisions:
  - "Notification-driven quit (appShouldQuit) decouples MenubarManager from AppDelegate terminate call, enabling the fade animation in the delegate before actual termination"
  - "visibleFrame used instead of screen.frame for default widget position — automatically excludes menu bar, notch, and Dock on all Mac models"
  - "clampToScreen() picks the screen with maximum overlap against widget rect, handles multi-monitor edge cases"
metrics:
  duration_minutes: 12
  completed_date: "2026-04-03"
  tasks_completed: 3
  files_changed: 5
---

# Quick Task 260403-tck: Smooth Quit, Safe Widget Positioning, Build Script

**One-liner:** Notification-driven graceful quit with NSAnimationContext fade-out, visibleFrame-based widget clamping, and standalone xcodebuild release script.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Smooth quit with fade-out and service cleanup | 4e2179e | ClaudeTokenMonitorApp.swift, FloatingWidgetWindow.swift, MenubarManager.swift |
| 2 | Safe widget positioning using visibleFrame | df75687 | FloatingWidgetWindow.swift |
| 3 | Standalone build script | c01b659 | build.sh, .gitignore |

## What Was Built

**Task 1 — Smooth Quit**

The quit flow is now:
1. Menu bar "Beenden" click -> `MenubarManager.quitApp()` posts `appShouldQuit` notification
2. `AppDelegate.handleGracefulQuit()` calls `gracefulQuit()`
3. `gracefulQuit()` calls `FloatingWidgetWindow.fadeOut(completion:)` — 0.25s NSAnimationContext alpha 1.0->0.0
4. In the completion block: all services stopped (`sessionWatcher.stop()`, `budgetMonitor.stop()`, `usageTracker.stop()`), then `NSApp.terminate(nil)`
5. `applicationWillTerminate` handles final cleanup (hide panel, remove observers) for force-quit path

**Task 2 — Safe Widget Positioning**

- `restoredOrigin()` validates saved UserDefaults position against all current screen `visibleFrame`s before using it; falls back to `defaultOrigin()` if off-screen
- `defaultOrigin()` uses `NSScreen.main?.visibleFrame` with 16px right / 8px top padding — safe on MacBook notch, with Dock, any menu bar height
- `clampToScreen(_:size:)` picks the screen with max overlap and constrains origin within its `visibleFrame`
- `didMoveNotification` now clamps before saving
- `NSApplication.didChangeScreenParametersNotification` re-clamps when displays connect/disconnect

**Task 3 — Build Script**

`ClaudeTokenMonitor/build.sh` (chmod +x):
- Cleans `build/` dir, runs `xcodebuild -configuration Release`, finds the `.app` in DerivedData, copies to `build/ClaudeTokenMonitor.app`
- Prints install/run instructions on success
- `ClaudeTokenMonitor/.gitignore` excludes `build/` and `.DS_Store`

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None.

## Self-Check: PASSED

- [x] ClaudeTokenMonitor/build.sh exists and is executable
- [x] ClaudeTokenMonitor/.gitignore exists
- [x] Commits 4e2179e, df75687, c01b659 present in git log
- [x] xcodebuild Debug and Release both succeeded
