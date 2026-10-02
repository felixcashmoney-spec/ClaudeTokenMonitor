import Foundation
import ServiceManagement
import os.log

@MainActor
final class LoginItemManager: ObservableObject {

    @Published private(set) var isEnabled: Bool = false
    private let logger = Logger(subsystem: "com.claudetokenmonitor", category: "LoginItemManager")

    init() {
        refresh()
    }

    /// Reads current registration state from SMAppService.
    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app as a Login Item.
    func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            refresh()
        } catch {
            // Surface error to console; UI observes isEnabled which reflects actual state.
            logger.error("Failed to toggle Login Item: \(error.localizedDescription)")
            refresh()
        }
    }
}
