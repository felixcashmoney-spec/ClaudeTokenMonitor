import AppKit
import SwiftUI

private let kPositionKey = "floatingWidgetPosition"

// MARK: - Shared expand state

@MainActor
final class WidgetExpandState: ObservableObject {
    @Published var isExpanded = false
    @Published var isFullScreenBackground = false
    var onResize: ((Bool) -> Void)?

    func toggle() {
        checkFullScreen()
        withAnimation(.easeInOut(duration: 0.35)) {
            isExpanded.toggle()
        }
    }
    
    func checkFullScreen() {
        guard let screen = NSScreen.main else { return }
        let w = screen.frame.width
        let h = screen.frame.height
        var foundFullscreen = false
        
        if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for window in windowList {
                if let layer = window[kCGWindowLayer as String] as? Int, layer == 0 {
                    if let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                       let rect = CGRect(dictionaryRepresentation: boundsDict) {
                          if abs(rect.width - w) < 2 && (h - rect.height) >= 0 && (h - rect.height) < 50 {
                              foundFullscreen = true
                              break
                          }
                    }
                }
            }
        }
        
        // Update state if different
        if isFullScreenBackground != foundFullscreen {
            isFullScreenBackground = foundFullscreen
        }
    }
}

// MARK: - Non-activating Panel

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Window Controller

@MainActor
final class FloatingWidgetWindow {

    private var panel: FloatingPanel?
    private let tracker: UsageWindowTracker
    private let expandState = WidgetExpandState()
    private let maxWidgetSize = NSSize(width: 310, height: 580)

    init(tracker: UsageWindowTracker) {
        self.tracker = tracker
    }

    func show() {
        if panel == nil { buildPanel() }
        panel?.orderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Animates the panel closed — shrinks + fades symmetrically to the open animation.
    func fadeOut(completion: @escaping () -> Void) {
        guard let p = panel else {
            completion()
            return
        }
        // First collapse if expanded
        if expandState.isExpanded {
            expandState.isExpanded = false
        }
        let oldFrame = p.frame
        // Shrink toward top-right corner while fading out
        let targetWidth: CGFloat = 60
        let targetHeight: CGFloat = 20
        let targetFrame = NSRect(
            x: oldFrame.maxX - targetWidth,
            y: oldFrame.maxY - targetHeight,
            width: targetWidth,
            height: targetHeight
        )
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            p.animator().setFrame(targetFrame, display: true)
            p.animator().alphaValue = 0.0
        }, completionHandler: {
            completion()
        })
    }

    private func buildPanel() {
        let rootView = FloatingWidgetView()
            .environmentObject(tracker)
            .environmentObject(expandState)

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: maxWidgetSize)

        let p = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: maxWidgetSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isMovableByWindowBackground = true // Allows dragging by clicking the visible notch area
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.contentView = hosting

        // Clear saved position once to pick up new notch-centered default
        let migrationKey = "widgetPositionMigrated_v2"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            UserDefaults.standard.removeObject(forKey: kPositionKey)
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
        p.setFrameOrigin(restoredOrigin())

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: p,
            queue: .main
        ) { [weak self, weak p] _ in
            guard let self, let p else { return }
            let clamped = self.clampToScreen(p.frame.origin, size: p.frame.size)
            if clamped != p.frame.origin {
                p.setFrameOrigin(clamped)
            }
            UserDefaults.standard.set(NSStringFromPoint(p.frame.origin), forKey: kPositionKey)
        }

        panel = p
    }

    private func restoredOrigin() -> NSPoint {
        if let saved = UserDefaults.standard.string(forKey: kPositionKey) {
            let pt = NSPointFromString(saved)
            if pt != .zero {
                let isOnScreen = NSScreen.screens.contains { screen in
                    let vf = screen.visibleFrame
                    return vf.contains(pt)
                }
                if isOnScreen {
                    return clampToScreen(pt, size: maxWidgetSize)
                }
            }
        }
        return defaultOrigin()
    }

    private func defaultOrigin() -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 100, y: 100) }
        let vf = screen.visibleFrame
        let fullFrame = screen.frame

        let topInset = fullFrame.maxY - vf.maxY
        let hasNotch = topInset > 30

        if hasNotch {
            let y = fullFrame.maxY - maxWidgetSize.height
            // Center horizontally under the notch
            return NSPoint(x: fullFrame.midX - (maxWidgetSize.width / 2), y: y)
        }

        // No notch: top-right with small padding
        return NSPoint(
            x: vf.maxX - maxWidgetSize.width - 16,
            y: fullFrame.maxY - maxWidgetSize.height - 8
        )
    }

    private func clampToScreen(_ origin: NSPoint, size: NSSize) -> NSPoint {
        let widgetRect = NSRect(origin: origin, size: size)
        let screen = NSScreen.screens.max(by: {
            widgetRect.intersection($0.frame).width * widgetRect.intersection($0.frame).height <
            widgetRect.intersection($1.frame).width * widgetRect.intersection($1.frame).height
        }) ?? NSScreen.main ?? NSScreen.screens.first
        guard let scr = screen else { return origin }

        let fullFrame = scr.frame
        let vf = scr.visibleFrame
        let topInset = fullFrame.maxY - vf.maxY
        let hasNotch = topInset > 30

        let maxY = hasNotch ? fullFrame.maxY - size.height : fullFrame.maxY - size.height - 8
        let x = min(max(origin.x, fullFrame.minX), fullFrame.maxX - size.width)
        let y = min(max(origin.y, vf.minY), maxY)
        return NSPoint(x: x, y: y)
    }
}
