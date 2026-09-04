import SwiftUI
import CorePersistence
import CalendarListFeature
import AppNavigation

struct RootContentView: View {
    @Environment(RootNavigation.self) var navigation
    let cache: CalendarCache

    var selectedCalendarID: Int64? {
        navigation.detailCalendarID
    }

    var body: some View {
        switch navigation.selectedSidebarCategory {
        case .calendarList, .none:
            CalendarListView(
                mode: .active,
                cache: cache,
                selectedCalendarID: selectedCalendarID,
                onSelectCalendar: { id in
                    navigation.goTo(.calendar(id, toRoot: false))
                }
            )
        case .archived:
            CalendarListView(
                mode: .archived,
                cache: cache,
                selectedCalendarID: selectedCalendarID,
                onSelectCalendar: { id in
                    navigation.goTo(.calendar(id, toRoot: false))
                }
            )
        }
    }
}
