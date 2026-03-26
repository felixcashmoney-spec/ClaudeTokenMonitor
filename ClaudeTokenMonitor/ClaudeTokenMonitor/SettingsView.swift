import SwiftUI

struct SettingsView: View {
    @StateObject private var loginItemManager = LoginItemManager()

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { loginItemManager.isEnabled },
                    set: { _ in loginItemManager.toggle() }
                ))
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 360, height: 120)
    }
}
