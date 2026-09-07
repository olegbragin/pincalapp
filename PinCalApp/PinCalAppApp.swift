import SwiftUI
import CorePersistence

@main
struct PinCalAppApp: App {
    @State private var session: PCCalendarSession

    init() {
        #if os(iOS)
        UITableView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = .clear
        #endif

        let storage = CalendarRepositoryFactory.makeDefault()
        _session = State(initialValue: PCCalendarSession(cache: CalendarCache(repository: storage)))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(\.calendarCache, session.cache)
        }
    }
}
