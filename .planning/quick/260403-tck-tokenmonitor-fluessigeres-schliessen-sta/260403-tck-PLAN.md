---
phase: quick-260403-tck
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - ClaudeTokenMonitor/ClaudeTokenMonitor/ClaudeTokenMonitorApp.swift
  - ClaudeTokenMonitor/ClaudeTokenMonitor/FloatingWidgetWindow.swift
  - ClaudeTokenMonitor/ClaudeTokenMonitor/MenubarManager.swift
  - ClaudeTokenMonitor/build.sh
autonomous: true
requirements: [QUIT-SMOOTH, BUILD-STANDALONE, LAYOUT-SAFE]
must_haves:
  truths:
    - "App quit has a visible fade-out animation before terminating"
    - "Services (SessionWatcher, BudgetMonitor, UsageWindowTracker) are stopped cleanly on quit"
    - "build.sh produces a .app bundle in build/ that launches independently"
    - "Floating widget default position accounts for menu bar height and does not overlap system UI"
  artifacts:
    - path: "ClaudeTokenMonitor/build.sh"
      provides: "Standalone build script"
    - path: "ClaudeTokenMonitor/ClaudeTokenMonitor/ClaudeTokenMonitorApp.swift"
      provides: "Smooth quit with fade-out and service cleanup"
    - path: "ClaudeTokenMonitor/ClaudeTokenMonitor/FloatingWidgetWindow.swift"
      provides: "Safe default position using screen.visibleFrame"
  key_links:
    - from: "MenubarManager.quitApp()"
      to: "AppDelegate cleanup"
      via: "NSApplication.terminate triggers applicationWillTerminate"
      pattern: "applicationWillTerminate"
---

<objective>
Three quality-of-life improvements for ClaudeTokenMonitor: (1) smooth fade-out animation and service cleanup on quit, (2) standalone build script for running without Xcode, (3) safe widget positioning that respects menu bar, notch, and Dock.

Purpose: Make the app feel polished when closing, runnable as a standalone .app, and non-obstructive on any Mac screen layout.
Output: Updated app lifecycle, new build.sh, improved widget positioning.
</objective>

<execution_context>
@/Users/felixleis/.claude/get-shit-done/workflows/execute-plan.md
@/Users/felixleis/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@ClaudeTokenMonitor/ClaudeTokenMonitor/ClaudeTokenMonitorApp.swift
@ClaudeTokenMonitor/ClaudeTokenMonitor/FloatingWidgetWindow.swift
@ClaudeTokenMonitor/ClaudeTokenMonitor/MenubarManager.swift
@ClaudeTokenMonitor/ClaudeTokenMonitor/SettingsView.swift
</context>

<tasks>

<task type="auto">
  <name>Task 1: Smooth quit with fade-out and service cleanup</name>
  <files>ClaudeTokenMonitor/ClaudeTokenMonitor/ClaudeTokenMonitorApp.swift, ClaudeTokenMonitor/ClaudeTokenMonitor/FloatingWidgetWindow.swift</files>
  <action>
In AppDelegate, add `applicationWillTerminate(_:)` and a new `gracefulQuit()` method:

1. Add `gracefulQuit()` to AppDelegate that:
   - Fades out the floating widget panel (animate alphaValue from 1.0 to 0.0 over 0.25s using NSAnimationContext)
   - Calls `sessionWatcher?.stop()`, `budgetMonitor?.stop()`, `usageTracker?.stop()` (add stop() methods if they don't exist — just set any timers to nil)
   - After the animation completes (use completionHandler), calls `NSApp.terminate(nil)`

2. In `applicationWillTerminate(_:)`:
   - Call `floatingWidget?.hide()` as final cleanup
   - Remove the NotificationCenter observer for "floatingWidgetToggled"

3. Add a `fadeOut(completion:)` method to FloatingWidgetWindow:
   - Uses NSAnimationContext with 0.25s duration
   - Animates panel.animator().alphaValue to 0.0
   - Calls completion block when done

4. In MenubarManager.quitApp(), instead of `NSApp.terminate(nil)`, post a notification `Notification.Name("appShouldQuit")`. In AppDelegate.applicationDidFinishLaunching, observe that notification and call `gracefulQuit()`.

This ensures the quit flow is: menu click -> notification -> fade-out animation -> service cleanup -> terminate.
  </action>
  <verify>
    <automated>cd /Users/felixleis/ClaudeCode/ClaudeTokenMonitor && xcodebuild -scheme ClaudeTokenMonitor -configuration Debug build 2>&1 | tail -5</automated>
  </verify>
  <done>App compiles. Quit from menu bar triggers a visible fade-out of the floating widget before the app terminates. Services are stopped cleanly.</done>
</task>

<task type="auto">
  <name>Task 2: Safe widget positioning using visibleFrame</name>
  <files>ClaudeTokenMonitor/ClaudeTokenMonitor/FloatingWidgetWindow.swift</files>
  <action>
Fix `restoredOrigin()` in FloatingWidgetWindow to use `screen.visibleFrame` instead of `screen.frame`:

1. Replace `restoredOrigin()` logic:
   - Use `NSScreen.main?.visibleFrame` (this automatically excludes menu bar at top, Dock at bottom/side, and accounts for the notch on MacBook Pro models)
   - Default position: top-right of visibleFrame with 16px padding from right edge and 8px padding from top
   - Calculation: `x = visibleFrame.maxX - collapsedSize.width - 16`, `y = visibleFrame.maxY - collapsedSize.height - 8`
   - Keep the saved-position restore path, but add bounds validation: if the saved position puts the widget outside any current screen's visibleFrame, reset to default

2. Add a `clampToScreen()` helper that ensures the widget origin is within screen.visibleFrame. Call it after restoring saved position AND after window move (in the didMoveNotification handler — clamp before saving).

3. Listen for `NSApplication.didChangeScreenParametersNotification` to re-clamp when displays change (e.g., external monitor disconnected).

This ensures the widget never overlaps the menu bar, notch area, or Dock regardless of Mac model or display configuration.
  </action>
  <verify>
    <automated>cd /Users/felixleis/ClaudeCode/ClaudeTokenMonitor && xcodebuild -scheme ClaudeTokenMonitor -configuration Debug build 2>&1 | tail -5</automated>
  </verify>
  <done>Widget default position uses visibleFrame, stays within safe area on all screen configurations. Saved positions are validated against current screen bounds.</done>
</task>

<task type="auto">
  <name>Task 3: Standalone build script</name>
  <files>ClaudeTokenMonitor/build.sh</files>
  <action>
Create `ClaudeTokenMonitor/build.sh` (chmod +x) that builds a standalone .app:

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="ClaudeTokenMonitor"

echo "Building $APP_NAME..."

# Clean previous build
rm -rf "$BUILD_DIR"

# Build release configuration
xcodebuild \
  -project "$SCRIPT_DIR/$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -destination 'generic/platform=macOS' \
  build

# Find and copy the .app bundle
APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "$APP_NAME.app" -type d | head -1)

if [ -z "$APP_PATH" ]; then
  echo "ERROR: $APP_NAME.app not found in build output"
  exit 1
fi

# Copy to build/ root for easy access
cp -R "$APP_PATH" "$BUILD_DIR/$APP_NAME.app"

echo ""
echo "Build complete: $BUILD_DIR/$APP_NAME.app"
echo ""
echo "To install:"
echo "  cp -R \"$BUILD_DIR/$APP_NAME.app\" ~/Applications/"
echo ""
echo "To run:"
echo "  open \"$BUILD_DIR/$APP_NAME.app\""
```

Also add `build/` to the project's .gitignore (create if needed at ClaudeTokenMonitor/.gitignore).
  </action>
  <verify>
    <automated>cd /Users/felixleis/ClaudeCode/ClaudeTokenMonitor && bash build.sh 2>&1 | tail -10</automated>
  </verify>
  <done>build.sh produces ClaudeTokenMonitor/build/ClaudeTokenMonitor.app that launches independently without Xcode. build/ is gitignored.</done>
</task>

</tasks>

<verification>
1. `xcodebuild build` succeeds without errors
2. build.sh produces a .app in build/ directory
3. The .app launches from Finder and shows the floating widget in a safe screen position
</verification>

<success_criteria>
- App quit triggers visible fade-out animation before terminating
- build.sh creates a standalone .app bundle
- Widget default position respects menu bar, notch, and Dock on all Mac models
</success_criteria>

<output>
After completion, create `.planning/quick/260403-tck-tokenmonitor-fluessigeres-schliessen-sta/260403-tck-SUMMARY.md`
</output>
