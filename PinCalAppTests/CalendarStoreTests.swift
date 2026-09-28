//
//  CalendarStoreTests.swift
//  PinCalAppTests
//
//  Exercises `CalendarStore` — the concrete `CalendarPersisting` — against a real in-memory
//  ObjectBox store, so the round trip the batch pipeline depends on is covered end to
//  end: a staged batch goes in with no id, and comes back with a real one.
//

import Testing
import Foundation
import ObjectBox
@testable import PinCalApp
import CoreDomain
// `@testable` for the internal `PP*` entities the assertions inspect directly.
@testable import CorePersistence

@MainActor
struct CalendarStoreTests {

    private let day = Date(timeIntervalSince1970: 1_780_000_000)

    private func makeStore() throws -> Store {
        try ObjectBoxFactory.makeInMemoryStore(named: "persisting-\(UUID().uuidString)")
    }

    /// The cache for setup and teardown, and the port under test. They are separate
    /// types on purpose: the point of the adapter is that the pipeline talks to the
    /// port and cannot reach the cache.
    private func makeFixture(store: Store) -> (cache: CalendarCache, port: any CalendarPersisting) {
        let cache = CalendarCache(repository: ObjectBoxCalendarStorage(store: store))
        return (cache, CalendarStore(cache: cache))
    }

    private func stagedBatch(name: String, on date: Date) -> CalendarEventBatch {
        CalendarEventBatch(
            name: name,
            colorName: "eventColorOption1",
            events: [CalendarEvent(name: "Event", date: date, colorName: "eventColorOption1")]
        )
    }

    /// `CalendarCache.createCalendar` returns nothing, so the assigned id is read back
    /// the way the rest of this package's tests do it.
    private func createCalendar(_ cache: CalendarCache, name: String = "Work") async throws -> Int64 {
        try await cache.createCalendar(name: name, year: 2026, numberOfColumns: 3)
        let all = try await cache.getAllCalendars()
        return try #require(all.first { $0.name == name }?.id)
    }

    @Test("calendar(id:) returns management data and no event graph")
    func calendarReturnsMetadata() async throws {
        let store = try makeStore()
        defer { store.close() }
        let fixture = makeFixture(store: store)
        let cache = fixture.cache
        let port = fixture.port

        let id = try await createCalendar(cache)
        let calendar = try await port.calendar(id: id)

        #expect(calendar?.name == "Work")
        #expect(calendar?.year == 2026)
        #expect(calendar?.numberOfColumns == 3)
        #expect(calendar?.isArchived == false)
    }

    @Test("calendar(id:) is nil for a calendar that does not exist")
    func calendarMissing() async throws {
        let store = try makeStore()
        defer { store.close() }
        let fixture = makeFixture(store: store)

        #expect(try await fixture.port.calendar(id: 9999) == nil)
    }

    @Test("eventBatches(calendarID:) is empty for a new calendar")
    func eventBatchesEmpty() async throws {
        let store = try makeStore()
        defer { store.close() }
        let fixture = makeFixture(store: store)
        let cache = fixture.cache
        let port = fixture.port

        let id = try await createCalendar(cache)

        #expect(try await port.eventBatches(calendarID: id).isEmpty)
    }

    @Test("A staged batch is written as new and comes back with a real id")
    func stagedBatchGetsAnID() async throws {
        let store = try makeStore()
        defer { store.close() }
        let fixture = makeFixture(store: store)
        let cache = fixture.cache
        let port = fixture.port

        let id = try await createCalendar(cache)
        let batch = stagedBatch(name: "Morning", on: day)
        #expect(batch.persistedID == nil)

        try await port.save(
            numberOfColumns: 3,
            eventBatches: [batch],
            forCalendar: id
        )

        let reloaded = try await port.eventBatches(calendarID: id)
        #expect(reloaded.count == 1)
        #expect(reloaded[0].persistedID != nil, "the store must have assigned an id")
        #expect(reloaded[0].name == "Morning")
        #expect(reloaded[0].events.count == 1)
        #expect(reloaded[0].events[0].persistedID != nil, "and one for its event")
    }

    @Test("The batch survives a write/read cycle with its content intact")
    func contentSurvivesRoundTrip() async throws {
        let store = try makeStore()
        defer { store.close() }
        let fixture = makeFixture(store: store)
        let cache = fixture.cache
        let port = fixture.port

        let id = try await createCalendar(cache)
        let original = stagedBatch(name: "Morning", on: day)
        try await port.save(numberOfColumns: 3, eventBatches: [original], forCalendar: id)

        let reloaded = try await port.eventBatches(calendarID: id)

        #expect(reloaded[0].hasSameContent(as: original, using: PCCalendarDataProvider()))
    }

    @Test("save writes the column count as well as the batches")
    func saveWritesColumns() async throws {
        let store = try makeStore()
        defer { store.close() }
        let fixture = makeFixture(store: store)
        let cache = fixture.cache
        let port = fixture.port

        let id = try await createCalendar(cache)
        try await port.save(numberOfColumns: 6, eventBatches: [], forCalendar: id)

        #expect(try await port.calendar(id: id)?.numberOfColumns == 6)
    }

    @Test("A second save updates the same batch rather than adding one")
    func secondSaveUpdatesInPlace() async throws {
        let store = try makeStore()
        defer { store.close() }
        let fixture = makeFixture(store: store)
        let cache = fixture.cache
        let port = fixture.port

        let id = try await createCalendar(cache)
        try await port.save(numberOfColumns: 3, eventBatches: [stagedBatch(name: "First", on: day)], forCalendar: id)

        let saved = try await port.eventBatches(calendarID: id)
        #expect(saved.count == 1)

        // Re-save the same batch, now carrying the id the store gave it.
        let renamed = saved[0].with(name: "Renamed")
        try await port.save(numberOfColumns: 3, eventBatches: [renamed], forCalendar: id)

        let after = try await port.eventBatches(calendarID: id)
        #expect(after.count == 1, "saving again must not append a duplicate")
        #expect(after[0].name == "Renamed")
        #expect(after[0].persistedID == saved[0].persistedID, "and must keep its identity")
    }

    @Test("Saving an empty batch list clears the calendar's batches")
    func emptySaveClears() async throws {
        let store = try makeStore()
        defer { store.close() }
        let fixture = makeFixture(store: store)
        let cache = fixture.cache
        let port = fixture.port

        let id = try await createCalendar(cache)
        try await port.save(numberOfColumns: 3, eventBatches: [stagedBatch(name: "Temp", on: day)], forCalendar: id)
        #expect(try await port.eventBatches(calendarID: id).count == 1)

        try await port.save(numberOfColumns: 3, eventBatches: [], forCalendar: id)

        #expect(try await port.eventBatches(calendarID: id).isEmpty)
        #expect(try store.box(for: PPEventBatch.self).all().isEmpty, "the rows must be gone, not orphaned")
    }

    @Test("Saving for a calendar that does not exist is a no-op, not a crash")
    func saveMissingCalendar() async throws {
        let store = try makeStore()
        defer { store.close() }
        let fixture = makeFixture(store: store)

        try await fixture.port.save(numberOfColumns: 3, eventBatches: [stagedBatch(name: "X", on: day)], forCalendar: 9999)

        #expect(try store.box(for: PPCalendar.self).all().isEmpty)
    }

    @Test("The store satisfies the port")
    func storeSatisfiesThePort() async throws {
        let store = try makeStore()
        defer { store.close() }
        let fixture = makeFixture(store: store)

        let id = try await createCalendar(fixture.cache)

        #expect(try await fixture.port.calendar(id: id) != nil)
        #expect(try await fixture.port.eventBatches(calendarID: id).isEmpty)
    }

    // MARK: - The EntityMappable seam

    @Test("A substituted mapper changes what the port returns, proving the seam is real")
    func mapperIsSubstitutable() async throws {
        let store = try makeStore()
        defer { store.close() }
        let cache = CalendarCache(repository: ObjectBoxCalendarStorage(store: store))
        let port = CalendarStore(cache: cache, mapper: UppercasingMapper())

        let id = try await createCalendar(cache)
        try await port.save(
            numberOfColumns: 3,
            eventBatches: [stagedBatch(name: "morning", on: day)],
            forCalendar: id
        )

        let reloaded = try await port.eventBatches(calendarID: id)
        #expect(reloaded.count == 1)
        #expect(reloaded[0].name == "MORNING", "the injected mapper did the translating, not RootMapper")
    }
}

// MARK: - The CalendarManaging side of the store

/// The calendar list's port, on the same concrete store. Separate suite because the
/// concerns differ: `CalendarPersisting` is the batch pipeline's narrow port, while
/// `CalendarManaging` is a screen's worth of load/create/rename/archive/restore/delete
/// plus the change feed it reacts to.
@MainActor
struct CalendarStoreManagingTests {

    private func makeStore() throws -> Store {
        try ObjectBoxFactory.makeInMemoryStore(named: "managing-\(UUID().uuidString)")
    }

    private func makeFixture(store: Store) -> (cache: CalendarCache, port: any CalendarManaging) {
        let cache = CalendarCache(repository: ObjectBoxCalendarStorage(store: store))
        return (cache, CalendarStore(cache: cache))
    }

    private func createCalendar(_ cache: CalendarCache, name: String = "Work") async throws -> Int64 {
        try await cache.createCalendar(name: name, year: 2026, numberOfColumns: 3)
        let all = try await cache.getAllCalendars()
        return try #require(all.first { $0.name == name }?.id)
    }

    @Test("The store satisfies the management port")
    func storeSatisfiesManaging() async throws {
        let store = try makeStore()
        defer { store.close() }
        let fixture = makeFixture(store: store)

        #expect(await fixture.port.loadActive().isEmpty)
        try await fixture.port.createCalendar(name: "Work", year: 2026, numberOfColumns: 3)
        #expect(await fixture.port.loadActive().count == 1)
    }

    @Test("loadActive and loadArchived partition by archive state")
    func loadsPartitionByArchiveState() async throws {
        let store = try makeStore()
        defer { store.close() }
        let fixture = makeFixture(store: store)

        let workId = try await createCalendar(fixture.cache, name: "Work")
        let oldId = try await createCalendar(fixture.cache, name: "Old")
        try await fixture.port.archiveCalendar(id: oldId)

        let active = await fixture.port.loadActive()
        let archived = await fixture.port.loadArchived()
        #expect(active.map(\.id) == [workId])
        #expect(active.allSatisfy { !$0.isArchived })
        #expect(archived.map(\.id) == [oldId])
        #expect(archived.allSatisfy { $0.isArchived })
    }

    @Test("Rename preserves the calendar's event batches")
    func renamePreservesBatches() async throws {
        let store = try makeStore()
        defer { store.close() }
        let cache = CalendarCache(repository: ObjectBoxCalendarStorage(store: store))
        let store_ = CalendarStore(cache: cache)
        let id = try await createCalendar(cache)

        try await store_.save(
            numberOfColumns: 3,
            eventBatches: [
                CalendarEventBatch(
                    name: "morning",
                    colorName: "eventColorOption1",
                    events: [CalendarEvent(name: "Event", date: Date(timeIntervalSince1970: 1_780_000_000), colorName: "eventColorOption1")]
                )
            ],
            forCalendar: id
        )
        #expect(try await store_.eventBatches(calendarID: id).count == 1)

        var renamed = try #require(await store_.calendar(id: id))
        renamed.name = "Renamed"
        try await store_.updateCalendar(renamed)

        // The point of the hazard: `PinCalendar` carries no event graph, so a naive
        // whole-value overwrite would write an empty batch list and delete real data.
        let batches = try await store_.eventBatches(calendarID: id)
        #expect(batches.count == 1, "renaming a calendar must not delete its batches")
        #expect(batches.first?.name == "morning")
        #expect(try await store_.calendar(id: id)?.name == "Renamed")
    }

    @Test("Archiving, restoring and deleting move the calendar between the two lists")
    func archiveRestoreDelete() async throws {
        let store = try makeStore()
        defer { store.close() }
        let fixture = makeFixture(store: store)
        let id = try await createCalendar(fixture.cache)

        try await fixture.port.archiveCalendar(id: id)
        #expect(await fixture.port.loadActive().isEmpty)
        #expect(await fixture.port.loadArchived().count == 1)

        try await fixture.port.restoreCalendar(id: id)
        #expect(await fixture.port.loadActive().count == 1)
        #expect(await fixture.port.loadArchived().isEmpty)

        try await fixture.port.permanentlyDeleteCalendar(id: id)
        #expect(await fixture.port.loadActive().isEmpty)
        // Read through the cache: the management port deliberately offers no
        // single-calendar read, so the test cannot accidentally depend on one.
        #expect(try await fixture.cache.getCalendar(id: id) == nil)
    }

    @Test("The change feed is bridged into domain changes")
    func changeFeedIsBridged() async throws {
        let store = try makeStore()
        defer { store.close() }
        let fixture = makeFixture(store: store)
        let stream = await fixture.port.changes()

        // A subscriber parked in the stream before the writes, since a feed with no
        // registered consumer drops what it is handed.
        let collector = ChangeCollector()
        let consumer = Task { for await change in stream { collector.append(change) } }
        try await Task.sleep(for: .milliseconds(100))

        let id = try await createCalendar(fixture.cache, name: "Work")
        try await fixture.port.updateCalendar(PinCalendar(id: id, name: "Renamed", year: 2026, numberOfColumns: 3))
        try await fixture.port.permanentlyDeleteCalendar(id: id)
        try await Task.sleep(for: .milliseconds(200))
        consumer.cancel()

        let changes = collector.all
        #expect(changes.contains(.added(PinCalendar(id: id, name: "Work", year: 2026, numberOfColumns: 3))))
        #expect(changes.contains(.changed(PinCalendar(id: id, name: "Renamed", year: 2026, numberOfColumns: 3))))
        #expect(changes.contains(.removed(PinCalendar(id: id, name: "Renamed", year: 2026, numberOfColumns: 3))))
        // Every change carries a `PinCalendar`, never a DTO. The compiler already
        // enforces that; what this adds is the guarantee that a change is actually
        // delivered per write rather than a single batched or dropped one.
        #expect(changes.count >= 3)
    }

    @Test("A substituted mapper is visible on the management port too")
    func mapperVisibleOnManaging() async throws {
        let store = try makeStore()
        defer { store.close() }
        let cache = CalendarCache(repository: ObjectBoxCalendarStorage(store: store))
        let port = CalendarStore(cache: cache, mapper: UppercasingMapper())

        let id = try await createCalendar(cache)
        try await port.archiveCalendar(id: id)

        #expect(await port.loadArchived().first?.name == "WORK")
    }
}

/// Thread-safe sink for the change-feed test; the consumer task is not main-actor bound.
private final class ChangeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var changes: [PinCalendarChange] = []

    func append(_ change: PinCalendarChange) {
        lock.lock()
        changes.append(change)
        lock.unlock()
    }

    var all: [PinCalendarChange] {
        lock.lock()
        defer { lock.unlock() }
        return changes
    }
}

/// A translation `RootMapper` would never perform, so a test can prove the mapper is a
/// real dependency rather than a hard-coded call.
private struct UppercasingMapper: EntityMappable {
    private let root = RootMapper()

    func calendar(from dto: CalendarDataSource) -> PinCalendar {
        var calendar = root.calendar(from: dto)
        calendar.name = dto.name.uppercased()
        return calendar
    }

    func event(from dto: EventDataSource) -> CalendarEvent {
        root.event(from: dto).with(name: dto.name.uppercased())
    }

    func eventBatch(from dto: EventBatchDataSource) -> CalendarEventBatch {
        let lifted = root.eventBatch(from: dto)
        return lifted
            .with(name: dto.name.uppercased())
            .with(events: dto.events.map { event(from: $0) })
    }

    func eventBatches(from dtos: [EventBatchDataSource]) -> [CalendarEventBatch] {
        dtos.map(eventBatch(from:))
    }

    func eventDataSource(from event: CalendarEvent) -> EventDataSource {
        root.eventDataSource(from: event)
    }

    func eventBatchDataSource(from batch: CalendarEventBatch) -> EventBatchDataSource {
        root.eventBatchDataSource(from: batch)
    }

    func eventBatchDataSources(from batches: [CalendarEventBatch]) -> [EventBatchDataSource] {
        batches.map(eventBatchDataSource(from:))
    }
}

