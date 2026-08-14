//
//  PinCalAppTests.swift
//  PinCalAppTests
//
//  Created by Oleg Bragin on 04.05.2026.
//

import Testing
import Foundation
import ObjectBox
@testable import PinCalApp

@MainActor
struct PinCalAppTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Swift Testing Documentation
        // https://developer.apple.com/documentation/testing
    }

    @Test func saveCalendarKeepsBatchEventsWhenRenaming() async throws {
        let store = try! Store(directoryPath: "memory:rename-\(UUID().uuidString)")
        defer { store.close() }

        let calendarBox = store.box(for: PPCalendar.self)
        let batchBox = store.box(for: PPEventBatch.self)
        let eventBox = store.box(for: PPEvent.self)

        let calendar = PPCalendar(name: "Test", year: 2026, numberOfColumns: 3)
        try calendarBox.put(calendar)
        let e1 = PPEvent(name: "A", color: "eventColorOption1", date: Date())
        let e2 = PPEvent(name: "B", color: "eventColorOption1", date: Date().addingTimeInterval(86400))
        try eventBox.put([e1, e2])
        let batch = PPEventBatch(title: "A", color: "eventColorOption1")
        try batchBox.put(batch)
        batch.events.replace([e1, e2])
        try batch.events.applyToDb()
        calendar.eventBatches.append(batch)
        try calendar.eventBatches.applyToDb()
        _ = try calendarBox.put(calendar)

        let storage = ObjectBoxCalendarStorage(store: store)
        var dto = CalendarDataSource(try calendarBox.get(calendar.id))!
        dto.eventBatches[0].name = "Renamed"
        _ = try await storage.saveCalendar(dto)

        let readBack = CalendarDataSource(try calendarBox.get(calendar.id))!
        #expect(readBack.eventBatches.count == 1)
        #expect(readBack.eventBatches[0].name == "Renamed")
        #expect(readBack.eventBatches[0].events.count == 2)
        #expect(try eventBox.all().count == 2)
    }

    @Test func saveCalendarDeletesOrphanedBatchAndItsEvents() async throws {
        let store = try! Store(directoryPath: "memory:delete-\(UUID().uuidString)")
        defer { store.close() }

        let calendarBox = store.box(for: PPCalendar.self)
        let batchBox = store.box(for: PPEventBatch.self)
        let eventBox = store.box(for: PPEvent.self)

        let calendar = PPCalendar(name: "Test", year: 2026, numberOfColumns: 3)
        try calendarBox.put(calendar)
        let e1 = PPEvent(name: "A", color: "eventColorOption1", date: Date())
        try eventBox.put(e1)
        let batch = PPEventBatch(title: "A", color: "eventColorOption1")
        try batchBox.put(batch)
        batch.events.replace([e1])
        try batch.events.applyToDb()
        calendar.eventBatches.append(batch)
        try calendar.eventBatches.applyToDb()
        _ = try calendarBox.put(calendar)

        let storage = ObjectBoxCalendarStorage(store: store)
        let empty = CalendarDataSource(id: Int64(calendar.id), name: "Test", year: 2026, numberOfColumns: 3, eventBatches: [])
        _ = try await storage.saveCalendar(empty)

        let readBack = CalendarDataSource(try calendarBox.get(calendar.id))!
        #expect(readBack.eventBatches.isEmpty)
        #expect(try batchBox.all().isEmpty)
        #expect(try eventBox.all().isEmpty)
    }

    @Test func saveCalendarKeepsEventsWhenAddingNewEvent() async throws {
        let store = try! Store(directoryPath: "memory:add-\(UUID().uuidString)")
        defer { store.close() }

        let calendarBox = store.box(for: PPCalendar.self)
        let batchBox = store.box(for: PPEventBatch.self)
        let eventBox = store.box(for: PPEvent.self)

        let calendar = PPCalendar(name: "Test", year: 2026, numberOfColumns: 3)
        try calendarBox.put(calendar)
        let e1 = PPEvent(name: "A", color: "eventColorOption1", date: Date())
        try eventBox.put(e1)
        let batch = PPEventBatch(title: "A", color: "eventColorOption1")
        try batchBox.put(batch)
        batch.events.replace([e1])
        try batch.events.applyToDb()
        calendar.eventBatches.append(batch)
        try calendar.eventBatches.applyToDb()
        _ = try calendarBox.put(calendar)

        let storage = ObjectBoxCalendarStorage(store: store)
        var dto = CalendarDataSource(try calendarBox.get(calendar.id))!
        dto.eventBatches[0].events.append(.init(name: "New", date: Date().addingTimeInterval(172800), color: "eventColorOption1"))
        _ = try await storage.saveCalendar(dto)

        let readBack = CalendarDataSource(try calendarBox.get(calendar.id))!
        #expect(readBack.eventBatches[0].events.count == 2)
        #expect(readBack.eventBatches[0].events.contains(where: { $0.name == "New" }))
        #expect(try eventBox.all().count == 2)
    }

}
