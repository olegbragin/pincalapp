import SwiftUI
import DSKit
import AppNavigation

struct RootDetailView: View {
    @Environment(RootNavigation.self) private var navigation
    @Environment(\.pcVibe) private var vibe

    var body: some View {
        @Bindable var bindableNavigation = navigation
        NavigationStack(path: $bindableNavigation.path) {
            ZStack {
                Rectangle()
                    .fill(vibe.color(for: .backgroundMain))
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
        .background(vibe.color(for: .backgroundMain))
    }
}
