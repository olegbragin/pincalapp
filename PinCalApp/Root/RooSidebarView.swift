import SwiftUI
import AppNavigation

struct RootSidebarView: View {
    @Environment(RootNavigation.self) private var navigation

    var body: some View {
        @Bindable var bindableNavigation = navigation
        List(selection: $bindableNavigation.selectedSidebarCategory) {
            Section("Menu") {
                Label("Calendars", systemImage: "calendar")
                    .tag(SidebarCategory.calendarList)
                    .accessibilityIdentifier("sidebar-calendars")
                Label("Archived", systemImage: "archivebox")
                    .tag(SidebarCategory.archived)
                    .accessibilityIdentifier("sidebar-archived")
                Label("Settings", systemImage: "gearshape")
                    .tag(SidebarCategory.settings)
                    .accessibilityIdentifier("sidebar-settings")
            }
        }
        .onChange(of: bindableNavigation.selectedSidebarCategory) { _, newCategory in
            if let category = newCategory {
                navigation.goTo(.sidebar(category))
            }
        }
        .navigationTitle("PinCal")
    }
}
