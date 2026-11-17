import SwiftData
import SwiftUI

@main
struct AuraLifeApp: App {
    private let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserConstitutionProfile.self,
            ConstitutionEvolutionRecord.self,
            RegimenPhase.self,
            DailyContextSnapshot.self,
            ActionCard.self,
            ChatAdjustmentLog.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("无法初始化 SwiftData ModelContainer: \(error)")
        }
    }()

    init() {
        GentleNotificationService.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
