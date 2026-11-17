import SwiftData
import SwiftUI

struct ContentView: View {
    @AppStorage("auralife.onboarding.completed") private var hasCompletedOnboarding: Bool = false
    @AppStorage("auralife.onboarding.migrated_existing") private var hasMigratedExistingUser: Bool = false
    @Query private var profiles: [UserConstitutionProfile]

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                TodayTimelineView()
            } else {
                OnboardingFlowView {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        hasMigratedExistingUser = true
                        hasCompletedOnboarding = true
                    }
                }
            }
        }
        .task {
            if !hasMigratedExistingUser {
                hasMigratedExistingUser = true
                if !profiles.isEmpty {
                    hasCompletedOnboarding = true
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewSupport.makeContainer())
}
