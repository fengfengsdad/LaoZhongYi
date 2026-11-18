import SwiftData
import SwiftUI

struct MainTabView: View {
    enum Tab: Hashable {
        case today
        case care
        case profile
    }

    @State private var selectedTab: Tab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayTimelineView(onNavigateToCareTab: {
                selectedTab = .care
            })
            .tabItem {
                Label("今日", systemImage: "sun.max.fill")
            }
            .tag(Tab.today)

            RegimenProgressView()
                .tabItem {
                    Label("调养", systemImage: "leaf.fill")
                }
                .tag(Tab.care)

            ProfileAndSettingsView()
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle")
                }
                .tag(Tab.profile)
        }
        .tint(AuraTheme.sageGreen)
    }
}

#Preview {
    MainTabView()
        .modelContainer(PreviewSupport.makeContainer())
}
