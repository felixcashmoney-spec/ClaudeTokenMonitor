import AppKit
import SwiftUI

private let kPositionKey = "floatingWidgetPosition"

// MARK: - Shared expand state

@MainActor
final class WidgetExpandState: ObservableObject {
    @Published var isExpanded = false
    var onResize: ((Bool) -> Void)?

    func toggle() {
        isExpanded.toggle()
        onResize?(isExpanded)
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

    private let collapsedSize = NSSize(width: 300, height: 44)
    private let expandedSize = NSSize(width: 300, height: 250)

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

    /// Animates the panel alpha to 0, then calls completion on the main thread.
    func fadeOut(completion: @escaping () -> Void) {
        guard let p = panel else {
            completion()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
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
        hosting.frame = NSRect(origin: .zero, size: collapsedSize)

        let p = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: collapsedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.contentView = hosting

        p.setFrameOrigin(restoredOrigin())

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: p,
            queue: .main
        ) { [weak p] _ in
            guard let origin = p?.frame.origin else { return }
            UserDefaults.standard.set(NSStringFromPoint(origin), forKey: kPositionKey)
        }

        expandState.onResize = { [weak self] expanded in
            self?.resizePanel(expanded: expanded)
        }

        panel = p
    }

    private func resizePanel(expanded: Bool) {
        guard let p = panel else { return }
        let newSize = expanded ? expandedSize : collapsedSize
        let oldFrame = p.frame
        // Keep top-right corner fixed: grow/shrink downward
        let newY = oldFrame.maxY - newSize.height
        let newFrame = NSRect(x: oldFrame.origin.x, y: newY, width: newSize.width, height: newSize.height)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            p.animator().setFrame(newFrame, display: true)
        }
    }

    private func restoredOrigin() -> NSPoint {
        if let saved = UserDefaults.standard.string(forKey: kPositionKey) {
            let pt = NSPointFromString(saved)
            if pt != .zero { return pt }
        }
        guard let screen = NSScreen.main else { return NSPoint(x: 100, y: 100) }
        let f = screen.frame
        return NSPoint(x: f.maxX - collapsedSize.width - 120, y: f.maxY - collapsedSize.height)
    }
}
