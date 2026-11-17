import Foundation
import SwiftData

@MainActor
enum PreviewSupport {
    static func makeContainer() -> ModelContainer {
        let schema = Schema([
            UserConstitutionProfile.self,
            DailyContextSnapshot.self,
            ActionCard.self,
            ChatAdjustmentLog.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        MockDataSeeder.seedIfNeeded(in: container.mainContext)
        return container
    }
}
