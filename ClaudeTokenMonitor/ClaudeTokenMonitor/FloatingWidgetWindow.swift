import AppKit
import SwiftUI

private let kPositionKey = "floatingWidgetPosition"

// MARK: - Draggable NSPanel subclass

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Window Controller

@MainActor
final class FloatingWidgetWindow: NSObject {

    private var panel: FloatingPanel?
    private weak var tracker: UsageWindowTracker?

    init(tracker: UsageWindowTracker) {
        self.tracker = tracker
        super.init()
    }

    func show() {
        if panel == nil {
            buildPanel()
        }
        panel?.orderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Private

    private func buildPanel() {
        guard let tracker else { return }

        let contentView = FloatingWidgetView()
            .environmentObject(tracker)

        let hosting = NSHostingView(rootView: contentView)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        // Size: let SwiftUI compute natural size first
        let naturalSize = hosting.fittingSize
        let panelWidth = max(naturalSize.width, 200)
        let panelHeight = max(naturalSize.height, 36)

        let p = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false          // we apply shadow in SwiftUI via .shadow() modifier
        p.hidesOnDeactivate = false
        p.contentView = hosting

        // Restore or default position
        p.setFrameOrigin(restoredOrigin(for: NSSize(width: panelWidth, height: panelHeight)))

        // Observe window-moved notifications to persist position
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowMoved(_:)),
            name: NSWindow.didMoveNotification,
            object: p
        )

        panel = p
    }

    private func restoredOrigin(for size: NSSize) -> NSPoint {
        if let saved = UserDefaults.standard.string(forKey: kPositionKey) {
            let pt = NSPointFromString(saved)
            if pt != .zero {
                return pt
            }
        }
        // Default: top-right of main screen with 20pt margin
        guard let screen = NSScreen.main else { return NSPoint(x: 100, y: 100) }
        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.maxX - size.width - 20
        let y = visibleFrame.maxY - size.height - 20
        return NSPoint(x: x, y: y)
    }

    @objc private func windowMoved(_ notification: Notification) {
        guard let p = panel else { return }
        let origin = p.frame.origin
        UserDefaults.standard.set(NSStringFromPoint(origin), forKey: kPositionKey)
    }
}
