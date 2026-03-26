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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let manager = MenubarManager()
        menubarManager = manager

        let watcher = SessionWatcher()
        let monitor = BudgetMonitor()
        sessionWatcher = watcher
        budgetMonitor = monitor

        let context = sharedModelContainer.mainContext
        watcher.start(modelContext: context)
        monitor.start(modelContext: context)
        manager.observeBudget(monitor)
    }
}
