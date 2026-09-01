//
//  TestDataSeeder.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 01.09.2026.
//

import Foundation
import ObjectBox

struct TestDataSeeder {
    static func seedUITestData(into store: Store) {
        let calendarBox = store.box(for: PPCalendar.self)
        let batchBox = store.box(for: PPEventBatch.self)
        let eventBox = store.box(for: PPEvent.self)

        let year = currentYear
        let month = Calendar.current.component(.month, from: Date())

        // Calendar 1: "UI Test Calendar" with one batch containing 2 events
        let calendar1 = PPCalendar(name: "UI Test Calendar", year: year, numberOfColumns: 2)
        _ = try? calendarBox.put(calendar1)

        let batch1 = PPEventBatch(title: "Women Cycle", color: "eventColorOption1")
        _ = try? batchBox.put(batch1)

        let events1 = [
            PPEvent(name: "Event1", color: "eventColorOption1", date: date(year: year, month: month, day: 10)),
            PPEvent(name: "Event1", color: "eventColorOption1", date: date(year: year, month: month, day: 12))
        ]
        try? eventBox.put(events1)
        batch1.events.replace(events1)
        try? batch1.events.applyToDb()

        guard let savedCal1 = try? calendarBox.get(calendar1.id) else { return }
        savedCal1.eventBatches.append(batch1)
        try? savedCal1.eventBatches.applyToDb()

        // Calendar 2: "Second Calendar"
        let calendar2 = PPCalendar(name: "Second Calendar", year: year, numberOfColumns: 3)
        _ = try? calendarBox.put(calendar2)

        // Calendar 3: "Third Calendar"
        let calendar3 = PPCalendar(name: "Third Calendar", year: year, numberOfColumns: 4)
        _ = try? calendarBox.put(calendar3)
    }

    static func seedBasicCalendar(
        into store: Store,
        name: String,
        year: Int = currentYear,
        columns: Int = 2
    ) -> PPCalendar {
        let calendarBox = store.box(for: PPCalendar.self)
        let calendar = PPCalendar(name: name, year: year, numberOfColumns: columns)
        _ = try? calendarBox.put(calendar)
        return calendar
    }

    static func seedEventBatch(
        into store: Store,
        calendar: PPCalendar,
        title: String,
        color: String,
        eventDays: [Int],
        year: Int = currentYear,
        month: Int = Calendar.current.component(.month, from: Date())
    ) -> PPEventBatch {
        let batchBox = store.box(for: PPEventBatch.self)
        let eventBox = store.box(for: PPEvent.self)
        let calendarBox = store.box(for: PPCalendar.self)

        let batch = PPEventBatch(title: title, color: color)
        _ = try? batchBox.put(batch)

        let events = eventDays.map { day in
            PPEvent(name: "Event1", color: color, date: date(year: year, month: month, day: day))
        }
        try? eventBox.put(events)
        batch.events.replace(events)
        try? batch.events.applyToDb()

        guard let savedCal = try? calendarBox.get(calendar.id) else { return batch }
        savedCal.eventBatches.append(batch)
        try? savedCal.eventBatches.applyToDb()

        return batch
    }

    // MARK: - Private Helpers

    static var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private static func date(year: Int, month: Int, day: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: day)
        return Calendar.current.date(from: components)!
    }
}