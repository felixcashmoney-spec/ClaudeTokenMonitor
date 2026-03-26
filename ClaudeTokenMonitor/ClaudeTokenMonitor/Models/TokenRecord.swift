import Foundation
import SwiftData

@Model
final class TokenRecord {
    var timestamp: Date
    var inputTokens: Int
    var outputTokens: Int
    var cacheCreationInputTokens: Int
    var cacheReadInputTokens: Int
    var isRateLimited: Bool

    var session: Session?

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationInputTokens + cacheReadInputTokens
    }

    init(timestamp: Date, inputTokens: Int, outputTokens: Int,
         cacheCreationInputTokens: Int, cacheReadInputTokens: Int,
         isRateLimited: Bool = false) {
        self.timestamp = timestamp
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.isRateLimited = isRateLimited
    }
}
