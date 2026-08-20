import SwiftUI

struct RootView: View {
    @State private var navigation = RootNavigation()

    var body: some View {
        NavigationSplitView {
            sidebarColumn
        } content: {
            RootContentView()
        } detail: {
            detailColumn
        }
        .environment(navigation)
    }

    private var sidebarColumn: some View {
        List(selection: $navigation.selectedCategory) {
            Section("Menu") {
                Label("Calendars", systemImage: "calendar")
                    .tag(RootSelection.calendarList)
                    .accessibilityIdentifier("sidebar-calendars")
                Label("Archived", systemImage: "archivebox")
                    .tag(RootSelection.archived)
                    .accessibilityIdentifier("sidebar-archived")
            }
        }
        .navigationTitle("PinCal")
    }

    private var detailColumn: some View {
        NavigationStack {
            if let id = navigation.selectedCalendarId {
                CalendarDetailView(calendarId: id)
            } else {
                ContentUnavailableView(
                    "Select a calendar",
                    systemImage: "calendar",
                    description: Text("Choose a calendar from the list")
                )
            }
        }
        .background(.colorBackgroundMain)
    }
}
