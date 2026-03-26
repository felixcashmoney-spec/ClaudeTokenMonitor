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

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menubarManager: MenubarManager?
    let sessionWatcher = SessionWatcher()
    let budgetMonitor = BudgetMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let manager = MenubarManager()
        menubarManager = manager

        let context = sharedModelContainer.mainContext
        sessionWatcher.start(modelContext: context)
        budgetMonitor.start(modelContext: context)
        manager.observeBudget(budgetMonitor)
    }
}
