import SwiftUI
import DSKit
import AppNavigation

struct RootDetailView: View {
    @Environment(RootNavigation.self) private var navigation

    var body: some View {
        @Bindable var bindableNavigation = navigation
        NavigationStack(path: $bindableNavigation.path) {
            ZStack {
                Rectangle()
                    .fill(Color.dsKit.colorBackgroundMain)
                    .ignoresSafeArea()
                if let id = navigation.detailCalendarID {
                    CalendarDetailView(calendarId: id)
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
