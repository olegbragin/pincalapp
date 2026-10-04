
import SwiftUI
import AppNavigation
import CalendarListFeature
import SettingsFeature

struct RootContentView: View {
    @Environment(RootNavigation.self) var navigation

    var selectedCalendarID: Int64? {
        navigation.detailCalendarID
    }

    /// A calendar left the active set, so stop showing it.
    ///
    /// The list is where calendars are watched, so it is what hears about this; the navigation
    /// owns what is on screen and is the only thing that can decide the calendar is closed. The
    /// close is conditional on the id, so the two can be wired without either knowing what the
    /// other is for — this fires for every calendar that leaves the set, and only the one that
    /// was on screen is closed.
    ///
    /// `Task` because the close ends the calendar's multi-select session, which awaits the
    /// store. Same reason selecting a calendar is wrapped: the route change happens after an
    /// async step, not instead of one.
    private func closeIfSelected(_ id: Int64) {
        Task { await navigation.closeCalendarIfSelected(id) }
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
                onCalendarRemoved: { id in closeIfSelected(id) },
                undoWindowDuration: PCCalendarSession.makeUndoWindowDuration()
            )
        case .archived:
            CalendarListView(
                mode: .archived,
                selectedCalendarID: selectedCalendarID,
                onSelectCalendar: { id in
                    Task { await navigation.switchCalendar(to: id) }
                },
                // Wired here as well as in the active list, and it is not redundant: deleting
                // for good is only reachable from this list, and that is the case where the
                // detail has the least to say — the row is gone from storage, so the detail
                // would fetch, find nothing and render nothing at all.
                onCalendarRemoved: { id in closeIfSelected(id) },
                undoWindowDuration: PCCalendarSession.makeUndoWindowDuration()
            )
        case .settings:
            SettingsView()
        }
    }
}
