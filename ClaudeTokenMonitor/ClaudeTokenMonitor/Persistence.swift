import SwiftData

/// Central ModelContainer for Claude Token Monitor.
/// Phase 2 registers Session and TokenRecord models here.
@MainActor
let sharedModelContainer: ModelContainer = {
    // No schema types yet — Phase 2 adds @Model classes here.
    let schema = Schema([])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    do {
        return try ModelContainer(for: schema, configurations: [config])
    } catch {
        fatalError("Failed to create ModelContainer: \(error)")
    }
}()
