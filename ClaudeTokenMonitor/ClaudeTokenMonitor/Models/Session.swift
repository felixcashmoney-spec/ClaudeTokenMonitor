import Foundation
import SwiftData

@Model
final class Session {
    @Attribute(.unique) var sessionId: String
    var projectPath: String
    var projectName: String
    var model: String
    var createdAt: Date
    var lastActivityAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TokenRecord.session)
    var tokenRecords: [TokenRecord] = []

    var totalInputTokens: Int {
        tokenRecords.reduce(0) { $0 + $1.inputTokens }
    }

    var totalOutputTokens: Int {
        tokenRecords.reduce(0) { $0 + $1.outputTokens }
    }

    var totalCacheCreationTokens: Int {
        tokenRecords.reduce(0) { $0 + $1.cacheCreationInputTokens }
    }

    var totalCacheReadTokens: Int {
        tokenRecords.reduce(0) { $0 + $1.cacheReadInputTokens }
    }

    var totalTokens: Int {
        totalInputTokens + totalOutputTokens + totalCacheCreationTokens + totalCacheReadTokens
    }

    init(sessionId: String, projectPath: String, model: String, createdAt: Date) {
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.projectName = (projectPath as NSString).lastPathComponent
        self.model = model
        self.createdAt = createdAt
        self.lastActivityAt = createdAt
    }
}
