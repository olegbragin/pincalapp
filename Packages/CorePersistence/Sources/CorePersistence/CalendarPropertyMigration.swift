import Foundation
import ObjectBox

enum CalendarPropertyMigration {
    private static let hasMigratedKey = "didMigrateCalendarProperties"

    static func runIfNeeded(store: Store) {
        guard !UserDefaults.standard.bool(forKey: hasMigratedKey) else { return }
        guard let calendars = try? store.box(for: PPCalendar.self).all(), !calendars.isEmpty else {
            UserDefaults.standard.set(true, forKey: hasMigratedKey)
            return
        }

        let calendarBox = store.box(for: PPCalendar.self)
        for calendar in calendars {
            _ = try? calendarBox.put(calendar)
        }

        UserDefaults.standard.set(true, forKey: hasMigratedKey)
    }
}
