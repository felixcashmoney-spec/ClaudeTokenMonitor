import Foundation
import ServiceManagement

@MainActor
final class LoginItemManager: ObservableObject {

    @Published private(set) var isEnabled: Bool = false

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
            print("[LoginItemManager] Failed to toggle Login Item: \(error)")
            refresh()
        }
    }
}
