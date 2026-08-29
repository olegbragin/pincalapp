import SwiftUI
import CorePersistence
import DSKit
import AppNavigation

struct RootDetailView: View {
    @Environment(RootNavigation.self) private var navigation
    let cache: CalendarCache

    var body: some View {
        @Bindable var bindableNavigation = navigation
        NavigationStack(path: $bindableNavigation.path) {
            ZStack {
                Rectangle()
                    .fill(Color.dsKit.colorBackgroundMain)
                    .ignoresSafeArea()
                if let id = navigation.detailCalendarID {
                    CalendarDetailView(calendarId: id, cache: cache)
                } else {
                    ContentUnavailableView(
                        "Select a calendar",
                        systemImage: "calendar",
                        description: Text("Choose a calendar from the list")
                    )
                }
            }
        }
        .background(Color.dsKit.colorBackgroundMain)
    }
}
