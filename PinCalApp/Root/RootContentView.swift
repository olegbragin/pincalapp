import SwiftUI
import CorePersistence
import CalendarListFeature
import AppNavigation

struct RootContentView: View {
    @Environment(RootNavigation.self) var navigation
    let cache: CalendarCache

    var selectedCalendarID: Int64? {
        if case .calendar(let id) = navigation.detailSelection {
            return id
        }
        return nil
    }

    var body: some View {
        switch navigation.selectedCategory {
        case .calendarList, .none:
            CalendarListView(
                mode: .active,
                cache: cache,
                selectedCalendarID: selectedCalendarID,
                onSelectCalendar: { id in
                    navigation.open(.calendar(id))
                }
            )
        case .archived:
            CalendarListView(
                mode: .archived,
                cache: cache,
                selectedCalendarID: selectedCalendarID,
                onSelectCalendar: { id in
                    navigation.open(.calendar(id))
                }
            )
        }
    }
}
