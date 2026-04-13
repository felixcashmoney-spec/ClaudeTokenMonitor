import SwiftUI
import SwiftData

@main
struct ClaudeTokenMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .modelContainer(sharedModelContainer)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var menubarManager: MenubarManager?
    private var sessionWatcher: SessionWatcher?
    private var budgetMonitor: BudgetMonitor?
    private var usageTracker: UsageWindowTracker?
    private var floatingWidget: FloatingWidgetWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let manager = MenubarManager()
        menubarManager = manager

        let watcher = SessionWatcher()
        let monitor = BudgetMonitor()
        let tracker = UsageWindowTracker()
        sessionWatcher = watcher
        budgetMonitor = monitor
        usageTracker = tracker

        let context = sharedModelContainer.mainContext
        watcher.start(modelContext: context)
        monitor.start(modelContext: context)
        tracker.start(modelContext: context)
        manager.observeBudget(monitor)
        manager.observeTracker(tracker)

        // Create floating widget and show if enabled (defaults to true on first launch)
        let widget = FloatingWidgetWindow(tracker: tracker)
        floatingWidget = widget
        let isEnabled = UserDefaults.standard.object(forKey: "floatingWidgetEnabled") as? Bool ?? true
        if isEnabled {
            widget.show()
        }

        // Listen for toggle notifications from SettingsView
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFloatingWidgetToggle(_:)),
            name: Notification.Name("floatingWidgetToggled"),
            object: nil
        )

        // Listen for graceful quit notification from menu bar
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGracefulQuit),
            name: Notification.Name("appShouldQuit"),
            object: nil
        )
    }

    @objc private func handleFloatingWidgetToggle(_ notification: Notification) {
        let isEnabled = UserDefaults.standard.bool(forKey: "floatingWidgetEnabled")
        if isEnabled {
            floatingWidget?.show()
        } else {
            floatingWidget?.hide()
        }
    }

    @objc private func handleGracefulQuit() {
        gracefulQuit()
    }

    /// Fades out the floating widget, stops all services, then terminates the app.
    func gracefulQuit() {
        if let widget = floatingWidget {
            widget.fadeOut { [weak self] in
                self?.stopServices()
                NSApp.terminate(nil)
            }
        } else {
            stopServices()
            NSApp.terminate(nil)
        }
    }

    private func stopServices() {
        sessionWatcher?.stop()
        budgetMonitor?.stop()
        usageTracker?.stop()
    }

    func applicationWillTerminate(_ notification: Notification) {
        floatingWidget?.hide()
        NotificationCenter.default.removeObserver(self, name: Notification.Name("floatingWidgetToggled"), object: nil)
        NotificationCenter.default.removeObserver(self, name: Notification.Name("appShouldQuit"), object: nil)
    }
}
