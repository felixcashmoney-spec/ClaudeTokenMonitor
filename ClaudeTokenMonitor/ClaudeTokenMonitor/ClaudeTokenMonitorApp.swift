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
    }
}
