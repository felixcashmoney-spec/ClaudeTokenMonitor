import AppKit
import SwiftUI

@MainActor
final class MenubarManager: NSObject, ObservableObject {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    override init() {
        super.init()
        setupStatusItem()
        setupPopover()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Claude Token Monitor")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 340)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenubarView()
                .modelContainer(sharedModelContainer)
        )
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
