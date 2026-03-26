import Foundation
import SwiftData
import UserNotifications

enum BudgetState: Equatable {
    case noBudget
    case ok(usagePercent: Double)
    case warning(usagePercent: Double, threshold: Double)
    case critical(usagePercent: Double, threshold: Double)
    case exceeded(usagePercent: Double)
}

@MainActor
final class BudgetMonitor: ObservableObject {
    @Published var state: BudgetState = .noBudget
    @Published var currentMonthTokens: Int = 0

    private var modelContext: ModelContext?
    private var timer: Timer?
    private var lastNotifiedThreshold: Double = 0

    func start(modelContext: ModelContext) {
        self.modelContext = modelContext
        requestNotificationPermission()
        evaluate()

        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluate()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func evaluate() {
        guard let modelContext else { return }

        // Get current month token usage
        let cal = Calendar.current
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        let descriptor = FetchDescriptor<TokenRecord>(
            predicate: #Predicate { $0.timestamp >= startOfMonth }
        )
        let records = (try? modelContext.fetch(descriptor)) ?? []
        currentMonthTokens = records.reduce(0) { $0 + $1.inputTokens + $1.outputTokens + $1.cacheCreationInputTokens + $1.cacheReadInputTokens }

        // Get budget settings
        let budgetDescriptor = FetchDescriptor<BudgetSettings>()
        let settings = (try? modelContext.fetch(budgetDescriptor))?.first

        guard let settings, settings.monthlyBudget > 0 else {
            state = .noBudget
            return
        }

        let usage = Double(currentMonthTokens) / Double(settings.monthlyBudget)

        if usage >= 1.0 {
            state = .exceeded(usagePercent: usage)
            sendNotificationIfNeeded(threshold: 1.0, usage: usage, enabled: settings.notificationsEnabled)
        } else if usage >= settings.warningThreshold2 {
            state = .critical(usagePercent: usage, threshold: settings.warningThreshold2)
            sendNotificationIfNeeded(threshold: settings.warningThreshold2, usage: usage, enabled: settings.notificationsEnabled)
        } else if usage >= settings.warningThreshold1 {
            state = .warning(usagePercent: usage, threshold: settings.warningThreshold1)
            sendNotificationIfNeeded(threshold: settings.warningThreshold1, usage: usage, enabled: settings.notificationsEnabled)
        } else {
            state = .ok(usagePercent: usage)
        }
    }

    private func sendNotificationIfNeeded(threshold: Double, usage: Double, enabled: Bool) {
        guard enabled, threshold > lastNotifiedThreshold else { return }
        lastNotifiedThreshold = threshold

        let content = UNMutableNotificationContent()
        content.title = "Claude Token Budget"
        if threshold >= 1.0 {
            content.body = "Monatliches Token-Budget überschritten! (\(Int(usage * 100))%)"
        } else {
            content.body = "Token-Verbrauch bei \(Int(usage * 100))% des monatlichen Budgets"
        }
        content.sound = .default

        let request = UNNotificationRequest(identifier: "budget-\(threshold)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
