import SwiftUI

struct RootContentView: View {
    @Environment(RootNavigation.self) var navigation

    var body: some View {
        switch navigation.selectedCategory {
        case .calendarList, .none:
            CalendarListView(mode: .active)
        case .archived:
            CalendarListView(mode: .archived)
        }
    }
}
