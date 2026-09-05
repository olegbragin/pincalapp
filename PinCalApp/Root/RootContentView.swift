import SwiftUI
import CalendarListFeature
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
                    navigation.goTo(.calendar(id, toRoot: false))
                }
            )
        case .archived:
            CalendarListView(
                mode: .archived,
                selectedCalendarID: selectedCalendarID,
                onSelectCalendar: { id in
                    navigation.goTo(.calendar(id, toRoot: false))
                }
            )
        }
    }
}
