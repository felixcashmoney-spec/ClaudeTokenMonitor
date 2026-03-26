import Foundation
import SwiftData

@Model
final class BudgetSettings {
    var monthlyBudget: Int
    var warningThreshold1: Double  // e.g. 0.5 = 50%
    var warningThreshold2: Double  // e.g. 0.8 = 80%
    var notificationsEnabled: Bool

    init(monthlyBudget: Int = 0, warningThreshold1: Double = 0.5,
         warningThreshold2: Double = 0.8, notificationsEnabled: Bool = true) {
        self.monthlyBudget = monthlyBudget
        self.warningThreshold1 = warningThreshold1
        self.warningThreshold2 = warningThreshold2
        self.notificationsEnabled = notificationsEnabled
    }
}
