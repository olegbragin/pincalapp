//
//  ObjectBoxFactory.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 19.02.2026.
//

import Foundation
import ObjectBox

struct ObjectBoxFactory {
    static let shared = ObjectBoxFactory()
    private(set) var store: Store!

    private init() {
        if ProcessInfo.processInfo.arguments.contains(Self.uiTestSeedArgument) {
            store = Self.seededStoreForUITests()
            return
        }
        let dbPath = getDatabasePath().path
        print("[ObjectBoxFactory] Opening store at: \(dbPath)")
        store = try! Store(directoryPath: dbPath)
        EventBatchMigration.runIfNeeded(store: store)
        CalendarPropertyMigration.runIfNeeded(store: store)
        let count = try? store.box(for: PPCalendar.self).count()
        print("[ObjectBoxFactory] Store opened. Calendar count: \(count ?? 0)")
    }

    static let uiTestSeedArgument = "-UITestSeedData"

    private static func seededStoreForUITests() -> Store {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("pincal-uitest-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(
            at: path,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let store = try! Store(directoryPath: path.path)
        seedForUITests(store: store)
        return store
    }

    private static func seedForUITests(store: Store) {
        let calendarBox = store.box(for: PPCalendar.self)
        let calendar = PPCalendar(name: "UI Test Calendar", year: currentYear, numberOfColumns: 2)
        try? calendarBox.put(calendar)

        let batch = PPEventBatch(title: "Women Cycle", color: PCColorOption.option1.colorName)
        let batchBox = store.box(for: PPEventBatch.self)
        try? batchBox.put(batch)

        let events = [
            PPEvent(name: "Event1", color: PCColorOption.option1.colorName, date: uiTestDate(day: 10)),
            PPEvent(name: "Event1", color: PCColorOption.option1.colorName, date: uiTestDate(day: 12))
        ]
        let eventBox = store.box(for: PPEvent.self)
        try? eventBox.put(events)
        batch.events.replace(events)
        try? batch.events.applyToDb()

        guard let savedCalendar = try? calendarBox.get(calendar.id) else { return }
        savedCalendar.eventBatches.append(batch)
        try? savedCalendar.eventBatches.applyToDb()

        let calendar2 = PPCalendar(name: "Second Calendar", year: currentYear, numberOfColumns: 3)
        try? calendarBox.put(calendar2)

        let calendar3 = PPCalendar(name: "Third Calendar", year: currentYear, numberOfColumns: 4)
        try? calendarBox.put(calendar3)
    }

    private static var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private static func uiTestDate(day: Int) -> Date {
        let calendar = Calendar.current
        let components = DateComponents(
            year: currentYear,
            month: calendar.component(.month, from: Date()),
            day: day
        )
        return calendar.date(from: components)!
    }

    private func getDatabasePath() -> URL {
        let databaseName = "p_calendars"
        let appSupport = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true)
            .appendingPathComponent(Bundle.main.bundleIdentifier!
        )
        let directory = appSupport.appendingPathComponent(databaseName)
        try! FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directory
    }
}
