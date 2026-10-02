import SwiftUI
import CalendarListFeature
import SettingsFeature
import AppNavigation

struct RootContentView: View {
    @Environment(RootNavigation.self) var navigation

    var selectedCalendarID: Int64? {
        navigation.detailCalendarID
    }

    var body: some View {
        switch navigation.selectedSidebarCategory {
        case .calendarList, .none:
            CalendarListView(
                mode: .active,
                selectedCalendarID: selectedCalendarID,
                onSelectCalendar: { id in
                    // Routed through `switchCalendar` so the store's guard gets a say: an
                    // unsaved write must not be abandoned by switching away from it. The
                    // reset-to-root behaviour lives there too — selecting from the list always
                    // resets the detail column to its root, unconditionally, including when
                    // `id` is the calendar already on screen. A tap is a request to show that
                    // calendar, and the honest response to "show me this" is the calendar
                    // itself, never a stale screen pushed on top of it. Deciding
                    // conditionally would make tapping a row do nothing when that row is the
                    // current one, so re-selecting became indistinguishable from a dead
                    // control.
                    Task { await navigation.switchCalendar(to: id) }
                },
                undoWindowDuration: PCCalendarSession.makeUndoWindowDuration()
            )
        case .archived:
            CalendarListView(
                mode: .archived,
                selectedCalendarID: selectedCalendarID,
                onSelectCalendar: { id in
                    Task { await navigation.switchCalendar(to: id) }
                },
                undoWindowDuration: PCCalendarSession.makeUndoWindowDuration()
            )
        case .settings:
            SettingsView()
        }
    }
}
