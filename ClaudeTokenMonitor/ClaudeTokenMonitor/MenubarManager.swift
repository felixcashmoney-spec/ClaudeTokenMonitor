import AppKit
import SwiftUI
import SwiftData
import Combine

@MainActor
final class MenubarManager: NSObject, ObservableObject {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var budgetMonitor: BudgetMonitor?
    private var cancellable: AnyCancellable?

    override init() {
        super.init()
        setupStatusItem()
        setupPopover()
    }

    func observeBudget(_ monitor: BudgetMonitor) {
        budgetMonitor = monitor
        cancellable = monitor.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.updateIcon(for: state)
            }
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
        popover.contentSize = NSSize(width: 400, height: 460)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenubarView()
                .modelContainer(sharedModelContainer)
        )
    }

    private func updateIcon(for state: BudgetState) {
        guard let button = statusItem.button else { return }
        switch state {
        case .noBudget, .ok:
            button.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Claude Token Monitor")
        case .warning:
            button.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Claude Token Monitor - Warnung")
            button.contentTintColor = .systemYellow
        case .critical:
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Claude Token Monitor - Kritisch")
            button.contentTintColor = .systemOrange
        case .exceeded:
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Claude Token Monitor - Budget überschritten")
            button.contentTintColor = .systemRed
        }
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
