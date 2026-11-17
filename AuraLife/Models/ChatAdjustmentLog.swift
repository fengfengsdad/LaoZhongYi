import Foundation
import SwiftData

@Model
final class ChatAdjustmentLog {
    var id: UUID
    var timestamp: Date
    var userInput: String
    var aiSummary: String
    var affectedCardTitles: [String]
    var wasApplied: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        userInput: String,
        aiSummary: String,
        affectedCardTitles: [String] = [],
        wasApplied: Bool = true
    ) {
        self.id = id
        self.timestamp = timestamp
        self.userInput = userInput
        self.aiSummary = aiSummary
        self.affectedCardTitles = affectedCardTitles
        self.wasApplied = wasApplied
    }
}
