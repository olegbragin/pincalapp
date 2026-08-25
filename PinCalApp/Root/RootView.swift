import SwiftUI

struct RootView: View {
    let cache: CalendarCache
    @State private var navigation = RootNavigation()
    @State private var keyboardState = PCKeyboardState()

    var body: some View {
        @Bindable var bindableNavigation = navigation
        return NavigationSplitView(preferredCompactColumn: $bindableNavigation.preferredCompactColumn) {
            sidebarColumn
        } content: {
            RootContentView(cache: cache)
        } detail: {
            detailColumn
        }
        .environment(navigation)
        .environment(keyboardState)
    }

    private var sidebarColumn: some View {
        @Bindable var bindableNavigation = navigation
        return List(selection: $bindableNavigation.selectedCategory) {
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
        @Bindable var bindableNavigation = navigation
        return NavigationStack(path: $bindableNavigation.path) {
            ZStack {
                Rectangle()
                    .fill(.colorBackgroundMain)
                    .ignoresSafeArea()
                if case .calendar(let id) = navigation.detailSelection {
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
        .background(.colorBackgroundMain)
    }
}
