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

    func applicationDidFinishLaunching(_ notification: Notification) {
        menubarManager = MenubarManager()
    }
}
