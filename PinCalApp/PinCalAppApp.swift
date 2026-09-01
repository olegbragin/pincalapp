import SwiftUI
import CorePersistence

@main
struct PinCalAppApp: App {
    @State private var cache: CalendarCache

    init() {
        UITableView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = .clear

        let storage: CalendarRepository
        if UITestStoreFactory.shouldSeedForUITests() {
            storage = ObjectBoxCalendarStorage(store: UITestStoreFactory.makeSeededStore())
        } else {
            storage = ObjectBoxCalendarStorage(store: ObjectBoxFactory.makePersistentStore())
        }
        _cache = State(initialValue: CalendarCache(repository: storage))
    }

    var body: some Scene {
        WindowGroup {
            RootView(cache: cache)
        }
    }
}
