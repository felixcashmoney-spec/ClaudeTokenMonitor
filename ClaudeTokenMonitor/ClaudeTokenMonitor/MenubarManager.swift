import AppKit
import SwiftUI
import SwiftData
import Combine

@MainActor
final class MenubarManager: NSObject, ObservableObject {

    private var statusItem: NSStatusItem!
    private var budgetMonitor: BudgetMonitor?
    private var usageTracker: UsageWindowTracker?
    private var cancellable: AnyCancellable?

    override init() {
        super.init()
        setupStatusItem()
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
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Claude Token Monitor")
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Einstellungen...", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Beenden", action: #selector(quitApp), keyEquivalent: "q")

        for item in menu.items {
            item.target = self
        }

        statusItem.menu = menu
    }

    private func updateIcon(for state: BudgetState) {
        guard let button = statusItem.button else { return }
        switch state {
        case .noBudget, .ok:
            button.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Claude Token Monitor")
            button.contentTintColor = nil
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

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NotificationCenter.default.post(name: Notification.Name("appShouldQuit"), object: nil)
    }
}
