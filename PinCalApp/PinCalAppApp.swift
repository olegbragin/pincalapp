import SwiftUI
import CorePersistence

@main
struct PinCalAppApp: App {
    @State private var cache = CalendarCache(repository: ObjectBoxCalendarStorage())

    init() {
        UITableView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = .clear
    }

    var body: some Scene {
        WindowGroup {
            RootView(cache: cache)
        }
    }
}
