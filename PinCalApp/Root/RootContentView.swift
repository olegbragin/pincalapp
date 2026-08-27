import SwiftUI
import CorePersistence
import CalendarListFeature

struct RootContentView: View {
    @Environment(RootNavigation.self) var navigation
    let cache: CalendarCache

    var body: some View {
        switch navigation.selectedCategory {
        case .calendarList, .none:
            CalendarListView(mode: .active, cache: cache)
        case .archived:
            CalendarListView(mode: .archived, cache: cache)
        }
    }
}
