import SwiftUI
import CorePersistence
import CoreDomain
import SingleCalendarFeature

@main
struct PinCalAppApp: App {
    @State private var session: PCCalendarSession

    init() {
        UITableView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = .clear

        let storage: CalendarRepository
        if UITestStoreFactory.shouldSeedForUITests() {
            storage = ObjectBoxCalendarStorage(store: UITestStoreFactory.makeSeededStore())
        } else {
            storage = ObjectBoxCalendarStorage(store: ObjectBoxFactory.makePersistentStore())
        }
        
        let dataProvider = PCCalendarDataProvider()
        let daySelectionManager = PCCalendarDaySelectionManager()
        _session = State(initialValue: PCCalendarSession(
                cache: CalendarCache(repository: storage),
                dataProvider: dataProvider,
                daySelectionManager: daySelectionManager,
                eventsSelectionManager: .init(
                    dataProvider: dataProvider,
                    daySelectionManager: daySelectionManager
                )
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(\.calendarCache, session.cache)
        }
    }
}
