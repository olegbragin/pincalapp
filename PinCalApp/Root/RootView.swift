import SwiftUI
import CoreDomain
import CorePersistence
import DSKit
import CalendarListFeature
import AppNavigation

struct RootView: View {
    let cache: CalendarCache
    @State private var navigation = RootNavigation()
    @State private var keyboardState = PCKeyboardState()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        @Bindable var bindableNavigation = navigation
        let compactBinding = Binding<NavigationSplitViewColumn>(
            get: { horizontalSizeClass == .compact ? navigation.preferredCompactColumn : .sidebar },
            set: { navigation.preferredCompactColumn = $0 }
        )
        return NavigationSplitView(preferredCompactColumn: compactBinding) {
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
        return List(selection: $bindableNavigation.selectedSidebarCategory) {
            Section("Menu") {
                Label("Calendars", systemImage: "calendar")
                    .tag(SidebarCategory.calendarList)
                    .accessibilityIdentifier("sidebar-calendars")
                Label("Archived", systemImage: "archivebox")
                    .tag(SidebarCategory.archived)
                    .accessibilityIdentifier("sidebar-archived")
            }
        }
        .onChange(of: bindableNavigation.selectedSidebarCategory) { _, newCategory in
            if let category = newCategory {
                navigation.goTo(.sidebar(category))
            }
        }
        .navigationTitle("PinCal")
    }

    private var detailColumn: some View {
        @Bindable var bindableNavigation = navigation
        return NavigationStack(path: $bindableNavigation.path) {
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
