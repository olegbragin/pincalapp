
import SwiftUI
import AppNavigation
import DSKit

struct RootSidebarView: View {
    @Environment(RootNavigation.self) private var navigation
    @Environment(\.pcVibe) private var vibe

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
                /// Shown only where `PCDiagnosticsGate` allows it.
                ///
                /// The row is hidden rather than the destination disabled: an entry that is
                /// visible and does nothing is worse than one that is absent, because it reads as a
                /// broken feature rather than an absent one.
                if PCDiagnosticsGate.isAvailable {
                    Label("Diagnostics", systemImage: "stethoscope")
                        .tag(SidebarCategory.diagnostics)
                        .accessibilityIdentifier("sidebar-diagnostics")
                }
            }
        }
        .onChange(of: bindableNavigation.selectedSidebarCategory) { _, newCategory in
            if let category = newCategory {
                navigation.goTo(.sidebar(category))
            }
        }
        .navigationTitle("PinCal")
        /// Themed on the list itself, not behind it.
        ///
        /// `RootView` already paints `backgroundMain` behind this column, and that is not enough:
        /// a `List` draws its own background over whatever is behind it, so the backdrop only
        /// ever showed in the gutter a collapsed sidebar leaves. The list has to be told to stop.
        ///
        /// `scrollContentBackground(.hidden)` is what removes it — without it the system grey
        /// persists no matter what colour is painted underneath.
        .scrollContentBackground(.hidden)
        .background(vibe.color(for: .backgroundMain))
        /// Reaching the screen edge is the same concern as above, and for the same reason: the
        /// theme has to continue past the safe area rather than stopping short of it.
        .background(vibe.color(for: .backgroundMain).ignoresSafeArea())
    }
}
