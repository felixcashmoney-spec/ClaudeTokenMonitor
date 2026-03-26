import SwiftData

@MainActor
let sharedModelContainer: ModelContainer = {
    let schema = Schema([Session.self, TokenRecord.self, BudgetSettings.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    do {
        return try ModelContainer(for: schema, configurations: [config])
    } catch {
        fatalError("Failed to create ModelContainer: \(error)")
    }
}()
