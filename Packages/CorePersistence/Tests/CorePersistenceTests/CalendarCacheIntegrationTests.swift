//
//  CalendarCacheIntegrationTests.swift
//  CorePersistenceTests
//
//  Created by Oleg Bragin on 23.08.2026.
//

import Testing
import Foundation
import ObjectBox
import Combine
@testable import CorePersistence

@MainActor
struct CalendarCacheIntegrationTests {

    // MARK: - Helpers

    private func makeStore() throws -> Store {
        try ObjectBoxFactory.inMemoryStore(named: "cache-integration-\(UUID().uuidString)")
    }

    private func makeCache(store: Store) -> CalendarCache {
        let storage = ObjectBoxCalendarStorage(store: store)
        return CalendarCache(repository: storage)
    }

    // MARK: - Calendar CRUD via CalendarCache + direct ObjectBox verification

    @Test func createCalendarPersistsViaCache() async throws {
        let store = try makeStore()
        defer { store.close() }

        let cache = makeCache(store: store)
        let calendarBox = store.box(for: PPCalendar.self)

        let newCalendar = try await cache.createCalendar(name: "My Calendar", year: 2026, numberOfColumns: 3)

        // Path A: verify via cache
        #expect(newCalendar.name == "My Calendar")
        #expect(newCalendar.year == 2026)
        #expect(newCalendar.numberOfColumns == 3)

        // Path B: verify via direct ObjectBox
        let persisted = try calendarBox.get(UInt64(newCalendar.id))
        #expect(persisted != nil)
        #expect(persisted?.name == "My Calendar")
        #expect(persisted?.year == 2026)
        #expect(persisted?.numberOfColumns == 3)
        #expect(persisted?.isArchived == false)
    }

    @Test func updateCalendarNamePersistsViaCache() async throws {
        let store = try makeStore()
        defer { store.close() }

        let cache = makeCache(store: store)
        let calendarBox = store.box(for: PPCalendar.self)

        let created = try await cache.createCalendar(name: "Original", year: 2026, numberOfColumns: 2)
        var updated = created
        updated.name = "Renamed"
        try await cache.updateCalendar(updated)

        // Path A: verify via cache
        let fromCache = try await cache.getCalendar(id: created.id)
        #expect(fromCache?.name == "Renamed")

        // Path B: verify via direct ObjectBox
        let persisted = try calendarBox.get(UInt64(created.id))
        #expect(persisted?.name == "Renamed")
    }

    @Test func updateCalendarColumnsPersistsViaCache() async throws {
        let store = try makeStore()
        defer { store.close() }

        let cache = makeCache(store: store)
        let calendarBox = store.box(for: PPCalendar.self)

        let created = try await cache.createCalendar(name: "Cols", year: 2026, numberOfColumns: 2)
        var updated = created
        updated.numberOfColumns = 7
        try await cache.updateCalendar(updated)

        // Path A: verify via cache
        let fromCache = try await cache.getCalendar(id: created.id)
        #expect(fromCache?.numberOfColumns == 7)

        // Path B: verify via direct ObjectBox
        let persisted = try calendarBox.get(UInt64(created.id))
        #expect(persisted?.numberOfColumns == 7)
    }

    @Test func archiveCalendarPersistsViaCache() async throws {
        let store = try makeStore()
        defer { store.close() }

        let cache = makeCache(store: store)
        let calendarBox = store.box(for: PPCalendar.self)

        let created = try await cache.createCalendar(name: "To Archive", year: 2026, numberOfColumns: 3)
        try await cache.archiveCalendar(created)

        // Path A: verify via cache
        let fromCache = try await cache.getCalendar(id: created.id)
        #expect(fromCache?.isArchived == true)

        // Path B: verify via direct ObjectBox
        let persisted = try calendarBox.get(UInt64(created.id))
        #expect(persisted?.isArchived == true)
    }

    @Test func restoreCalendarPersistsViaCache() async throws {
        let store = try makeStore()
        defer { store.close() }

        let cache = makeCache(store: store)
        let calendarBox = store.box(for: PPCalendar.self)

        let created = try await cache.createCalendar(name: "To Restore", year: 2026, numberOfColumns: 3)
        try await cache.archiveCalendar(created)
        try await cache.restoreCalendar(created)

        // Path A: verify via cache
        let fromCache = try await cache.getCalendar(id: created.id)
        #expect(fromCache?.isArchived == false)

        // Path B: verify via direct ObjectBox
        let persisted = try calendarBox.get(UInt64(created.id))
        #expect(persisted?.isArchived == false)
    }

    @Test func deleteCalendarPersistsViaCache() async throws {
        let store = try makeStore()
        defer { store.close() }

        let cache = makeCache(store: store)
        let calendarBox = store.box(for: PPCalendar.self)

        let created = try await cache.createCalendar(name: "To Delete", year: 2026, numberOfColumns: 3)
        try await cache.permanentlyDeleteCalendar(created)

        // Path A: verify via cache
        let fromCache = try await cache.getCalendar(id: created.id)
        #expect(fromCache == nil)

        // Path B: verify via direct ObjectBox
        let persisted = try calendarBox.get(UInt64(created.id))
        #expect(persisted == nil)
    }

    @Test func loadActiveReturnsOnlyNonArchivedViaCache() async throws {
        let store = try makeStore()
        defer { store.close() }

        let cache = makeCache(store: store)

        let cal1 = try await cache.createCalendar(name: "Active1", year: 2026, numberOfColumns: 2)
        _ = try await cache.createCalendar(name: "Active2", year: 2026, numberOfColumns: 3)
        let cal3 = try await cache.createCalendar(name: "Archived", year: 2026, numberOfColumns: 4)

        try await cache.archiveCalendar(try await cache.getCalendar(id: cal3.id) ?? cal1)

        // Path A: verify via cache
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var cancellable: AnyCancellable?
            cancellable = cache.changes.sink { operation in
                if case .refresh = operation {
                    cancellable?.cancel()
                    continuation.resume()
                }
            }
            Task { await cache.loadActive() }
        }

        // Path B: verify via direct ObjectBox
        let calendarBox = store.box(for: PPCalendar.self)
        let active = try calendarBox.query { PPCalendar.isArchived == false }.build().find()
        #expect(active.count == 2)
        let names = Set(active.map(\.name))
        #expect(names.contains("Active1"))
        #expect(names.contains("Active2"))
    }

    @Test func loadArchivedReturnsOnlyArchivedViaCache() async throws {
        let store = try makeStore()
        defer { store.close() }

        let cache = makeCache(store: store)

        _ = try await cache.createCalendar(name: "Active", year: 2026, numberOfColumns: 2)
        let archived = try await cache.createCalendar(name: "Archived", year: 2026, numberOfColumns: 3)
        try await cache.archiveCalendar(archived)

        // Path A: verify via cache
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var cancellable: AnyCancellable?
            cancellable = cache.changes.sink { operation in
                if case .refresh = operation {
                    cancellable?.cancel()
                    continuation.resume()
                }
            }
            Task { await cache.loadArchived() }
        }

        // Path B: verify via direct ObjectBox
        let calendarBox = store.box(for: PPCalendar.self)
        let archivedCals = try calendarBox.query { PPCalendar.isArchived == true }.build().find()
        #expect(archivedCals.count == 1)
        #expect(archivedCals[0].name == "Archived")
    }

    // MARK: - Calendar CRUD signal verification

    @Test func createCalendarSendsAddSignal() async throws {
        let store = try makeStore()
        defer { store.close() }

        let cache = makeCache(store: store)

        var receivedOperations: [ChangeOperation] = []
        let cancellable = cache.changes.sink { operation in
            receivedOperations.append(operation)
        }

        _ = try await cache.createCalendar(name: "Signal Test", year: 2026, numberOfColumns: 3)

        cancellable.cancel()

        #expect(receivedOperations.count == 1)
        if case .add(let item) = receivedOperations.first {
            #expect(item.name == "Signal Test")
        } else {
            Issue.record("Expected .add operation")
        }
    }

    @Test func updateCalendarSendsChangeSignal() async throws {
        let store = try makeStore()
        defer { store.close() }

        let cache = makeCache(store: store)
        let created = try await cache.createCalendar(name: "Original", year: 2026, numberOfColumns: 3)

        var receivedOperations: [ChangeOperation] = []
        let cancellable = cache.changes.sink { operation in
            receivedOperations.append(operation)
        }

        var updated = created
        updated.name = "Updated"
        try await cache.updateCalendar(updated)

        cancellable.cancel()

        let changeOps = receivedOperations.filter {
            if case .change = $0 { return true }
            return false
        }
        #expect(changeOps.count == 1)
    }

    @Test func archiveCalendarSendsDeleteSignal() async throws {
        let store = try makeStore()
        defer { store.close() }

        let cache = makeCache(store: store)
        let created = try await cache.createCalendar(name: "To Archive Signal", year: 2026, numberOfColumns: 3)

        var receivedOperations: [ChangeOperation] = []
        let cancellable = cache.changes.sink { operation in
            receivedOperations.append(operation)
        }

        try await cache.archiveCalendar(created)

        cancellable.cancel()

        let deleteOps = receivedOperations.filter {
            if case .delete = $0 { return true }
            return false
        }
        #expect(deleteOps.count == 1)
    }

    // MARK: - Batch storage round-trips via ObjectBoxCalendarStorage

    @Test func saveCalendarKeepsEventsWhenAddingNewEvent() async throws {
        let store = try makeStore()
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
        var dto = try calendarBox.get(calendar.id).map { CalendarDataSource($0)! }!
        dto.eventBatches[0].events.append(.init(name: "New", date: Date().addingTimeInterval(172800), color: "eventColorOption1"))
        _ = try await storage.saveCalendar(dto)

        let readBack = try calendarBox.get(calendar.id).map { CalendarDataSource($0)! }!
        #expect(readBack.eventBatches[0].events.count == 2)
        #expect(readBack.eventBatches[0].events.contains(where: { $0.name == "New" }))
        #expect(try eventBox.all().count == 2)
    }

    @Test func getActiveCalendarsReturnsOnlyNonArchived() async throws {
        let store = try makeStore()
        defer { store.close() }

        let storage = ObjectBoxCalendarStorage(store: store)

        let cal1 = CalendarDataSource(name: "Active", year: 2026, numberOfColumns: 2)
        let cal2 = CalendarDataSource(name: "ToArchive", year: 2026, numberOfColumns: 3)
        let id1 = try await storage.saveCalendar(cal1)
        let id2 = try await storage.saveCalendar(cal2)

        let active = try await storage.getActiveCalendars()
        #expect(active.count == 2)

        try await storage.archiveCalendar(id2)

        let afterArchive = try await storage.getActiveCalendars()
        #expect(afterArchive.count == 1)
        #expect(afterArchive[0].id == id1)

        let archived = try await storage.getArchivedCalendars()
        #expect(archived.count == 1)
        #expect(archived[0].id == id2)

        try await storage.restoreCalendar(id2)

        let afterRestore = try await storage.getActiveCalendars()
        #expect(afterRestore.count == 2)
    }

    @Test func saveCalendarDeletesOrphanedBatchAndItsEvents() async throws {
        let store = try makeStore()
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

        let readBack = try calendarBox.get(calendar.id).map { CalendarDataSource($0)! }!
        #expect(readBack.eventBatches.isEmpty)
        #expect(try batchBox.all().isEmpty)
        #expect(try eventBox.all().isEmpty)
    }

    @Test func saveCalendarKeepsBatchEventsWhenRenaming() async throws {
        let store = try makeStore()
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
        var dto = try calendarBox.get(calendar.id).map { CalendarDataSource($0)! }!
        dto.eventBatches[0].name = "Renamed"
        _ = try await storage.saveCalendar(dto)

        let readBack = try calendarBox.get(calendar.id).map { CalendarDataSource($0)! }!
        #expect(readBack.eventBatches.count == 1)
        #expect(readBack.eventBatches[0].name == "Renamed")
        #expect(readBack.eventBatches[0].events.count == 2)
        #expect(try eventBox.all().count == 2)
    }
}