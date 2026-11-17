import SwiftData
import SwiftUI

struct ContentView: View {
    var body: some View {
        TodayTimelineView()
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewSupport.makeContainer())
}
