import SwiftUI

struct RootContentView: View {
    @Environment(RootNavigation.self) var navigation

    var body: some View {
        switch navigation.selectedCategory {
        case .calendarList, .none:
            CalendarListView()
        case .archived:
            ContentUnavailableView(
                "Archived calendars",
                systemImage: "archivebox",
                description: Text("Coming soon")
            )
        case .calendar:
            CalendarListView()
        }
    }
}
