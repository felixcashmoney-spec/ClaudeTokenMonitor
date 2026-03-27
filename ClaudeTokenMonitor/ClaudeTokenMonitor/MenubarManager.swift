import AppKit
import SwiftUI
import SwiftData
import Combine

@MainActor
final class MenubarManager: NSObject, ObservableObject {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var budgetMonitor: BudgetMonitor?
    private var usageTracker: UsageWindowTracker?
    private var cancellable: AnyCancellable?
    nonisolated(unsafe) private var globalKeyMonitor: Any?
    nonisolated(unsafe) private var localKeyMonitor: Any?

    override init() {
        super.init()
        setupStatusItem()
        setupPopover()
        setupKeyboardShortcut()
    }

    deinit {
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// Set up Cmd+Shift+T global keyboard shortcut to toggle the popover.
    private func setupKeyboardShortcut() {
        // Global monitor: catches shortcut when app is in the background
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.command, .shift])
                && event.charactersIgnoringModifiers?.lowercased() == "t" {
                Task { @MainActor in
                    self?.togglePopover(nil)
                }
            }
        }

        // Local monitor: catches shortcut when the app window is active; consumes the event
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.command, .shift])
                && event.charactersIgnoringModifiers?.lowercased() == "t" {
                Task { @MainActor in
                    self?.togglePopover(nil)
                }
                return nil  // consume the event
            }
            return event
        }
    }

    func observeBudget(_ monitor: BudgetMonitor) {
        budgetMonitor = monitor
        cancellable = monitor.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.updateIcon(for: state)
            }
    }

    func observeTracker(_ tracker: UsageWindowTracker) {
        usageTracker = tracker
        updatePopoverContent()
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
        updatePopoverContent()
    }

    private func updatePopoverContent() {
        let rootView: AnyView
        if let tracker = usageTracker {
            rootView = AnyView(
                MenubarView()
                    .modelContainer(sharedModelContainer)
                    .environmentObject(tracker)
            )
        } else {
            rootView = AnyView(
                MenubarView()
                    .modelContainer(sharedModelContainer)
            )
        }
        popover.contentViewController = NSHostingController(rootView: rootView)
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
