import Foundation
import SwiftData

@Model
final class ActionCard {
    var id: UUID
    var categoryRawValue: String
    var timeSlot: String
    var title: String
    var actionDetail: String
    var reasoning: String
    var isCompleted: Bool
    var sortOrder: Int
    var snapshot: DailyContextSnapshot?

    var category: ActionCategory {
        get { ActionCategory(rawValue: categoryRawValue) ?? .lifestyle }
        set { categoryRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        category: ActionCategory,
        timeSlot: String,
        title: String,
        actionDetail: String,
        reasoning: String,
        isCompleted: Bool = false,
        sortOrder: Int = 0,
        snapshot: DailyContextSnapshot? = nil
    ) {
        self.id = id
        self.categoryRawValue = category.rawValue
        self.timeSlot = timeSlot
        self.title = title
        self.actionDetail = actionDetail
        self.reasoning = reasoning
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.snapshot = snapshot
    }
}
