import SwiftUI
import SwiftData

struct SettingsView: View {
    @StateObject private var loginItemManager = LoginItemManager()
    @Query private var budgetSettings: [BudgetSettings]
    @Environment(\.modelContext) private var modelContext

    private var settings: BudgetSettings {
        if let existing = budgetSettings.first {
            return existing
        }
        let new = BudgetSettings()
        modelContext.insert(new)
        try? modelContext.save()
        return new
    }

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { loginItemManager.isEnabled },
                    set: { _ in loginItemManager.toggle() }
                ))
            }

            Section("Monatliches Token-Budget") {
                HStack {
                    Text("Budget")
                    Spacer()
                    TextField("Tokens", value: Binding(
                        get: { settings.monthlyBudget },
                        set: { settings.monthlyBudget = $0; try? modelContext.save() }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .multilineTextAlignment(.trailing)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.yellow)
                        Text("Warnung 1")
                        Spacer()
                        Text("\(Int(settings.warningThreshold1 * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40)
                    }
                    Slider(value: Binding(
                        get: { settings.warningThreshold1 },
                        set: { settings.warningThreshold1 = $0; try? modelContext.save() }
                    ), in: 0.1...0.9, step: 0.05)
                    .tint(.yellow)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Warnung 2")
                        Spacer()
                        Text("\(Int(settings.warningThreshold2 * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40)
                    }
                    Slider(value: Binding(
                        get: { settings.warningThreshold2 },
                        set: { settings.warningThreshold2 = $0; try? modelContext.save() }
                    ), in: 0.1...0.99, step: 0.05)
                    .tint(.orange)
                }

                Toggle("Benachrichtigungen", isOn: Binding(
                    get: { settings.notificationsEnabled },
                    set: { settings.notificationsEnabled = $0; try? modelContext.save() }
                ))
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 440, height: 360)
    }
}
