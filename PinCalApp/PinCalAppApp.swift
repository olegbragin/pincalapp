import SwiftUI
import CorePersistence
import ObjectBox

@main
struct PinCalAppApp: App {
    @State private var cache: CalendarCache

    init() {
        UITableView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = .clear

        let store: Store
        if UITestStoreFactory.shouldSeedForUITests() {
            store = UITestStoreFactory.makeSeededStore()
        } else {
            store = try! ObjectBoxFactory.makePersistentStore()
        }
        let storage = ObjectBoxCalendarStorage(store: store)
        _cache = State(initialValue: CalendarCache(repository: storage))
    }

    var body: some Scene {
        WindowGroup {
            RootView(cache: cache)
        }
    }
}