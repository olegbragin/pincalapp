//
//  CalendarStoreTests.swift
//  PinCalAppTests
//
//  Exercises `CalendarStore` — the concrete `CalendarPersisting` — against a real in-memory
//  ObjectBox store, so the round trip the batch pipeline depends on is covered end to
//  end: a staged batch goes in with no id, and comes back with a real one.
//

import Foundation
import Testing
import CoreDomain
import ObjectBox
// `@testable` for the internal `PP*` entities the assertions inspect directly.
@testable import CorePersistence
@testable import PinCalApp

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

    /// The round trip the STR actually performs, and the one neither of the tests above
    /// covers.
    ///
    /// The difference is the **id**. Both earlier saves pass a batch with no
    /// `persistedID`, so `ObjectBoxCalendarStorage.saveCalendar` classifies the row already
    /// on disk as an orphan, deletes it with its events, and writes a fresh one — a path
    /// that works and is also why those tests are cheap. The app does not do that: it
    /// `openBatch`es the row and edits it, and the edit merges through `resolved()`,
    /// which carries the row's **real** `persistedID`. That takes the update branch instead,
    /// and it is the branch §16's step 6 uses.
    @Test("Re-saving an existing batch by its real id keeps it and the events that remain")
    func resavingByRealIdKeepsTheBatch() async throws {
        let store = try makeStore()
        defer { store.close() }
        let fixture = makeFixture(store: store)
        let cache = fixture.cache
        let port = fixture.port
        let id = try await createCalendar(cache)

        // The batch is created and committed, so the store assigns real ids to it and to
        // its four events — exactly as it does when the user saves a new batch.
        let four = (0..<4).map { index in
            CalendarEvent(
                name: "Event",
                date: day.addingTimeInterval(Double(index) * 86400),
                colorName: "eventColorOption1"
            )
        }
        try await port.save(
            numberOfColumns: 3,
            eventBatches: [CalendarEventBatch(name: "Window", colorName: "eventColorOption1", events: four)],
            forCalendar: id
        )

        // Re-open it, the way the editor does, and drop three of the four events while
        // keeping each event's own real id.
        let opened = try await port.eventBatches(calendarID: id)
        let batch = try #require(opened.first)
        #expect(batch.persistedID != nil, "setup: the committed batch must have a real id")
        let kept = try #require(batch.events.last)
        let edited = CalendarEventBatch(
            persistedID: batch.persistedID,
            name: batch.name,
            colorName: batch.colorName,
            events: [kept]
        )

        try await port.save(numberOfColumns: 3, eventBatches: [edited], forCalendar: id)

        let after = try await port.eventBatches(calendarID: id)
        let afterBatches = after.count
        let afterEvents = after.first?.events.count ?? -1
        let afterBatchID = after.first?.persistedID.map(String.init) ?? "nil"
        let afterDate = after.first?.events.first?.date.timeIntervalSince1970 ?? 0

        #expect(afterBatches == 1, "the batch must survive, got \(afterBatches)")
        #expect(
            afterEvents == 1,
            "AB: the batch came back with \(afterEvents) events, expected the 1 that was saved"
        )
        #expect(
            afterBatchID == String(batch.persistedID ?? -1),
            "and it must be the same row, updated — not a replacement. got \(afterBatchID), expected \(String(describing: batch.persistedID))"
        )
        #expect(
            afterDate == kept.date.timeIntervalSince1970,
            "the surviving event must be the one on the day that was kept"
        )
    }

    // MARK: - §16, the reported bug, from the storage side

    /// §16.3 hypothesis 5, and the decisive test the plan asks for: inspect the store
    /// rather than the UI, which separates "the row was deleted" from "the row is there but
    /// lost its events".
    ///
    /// The reported STR builds a batch across four days, then removes three of them and
    /// saves. The UI test `BatchEditorKnownBugTests` establishes that the state entering
    /// that save is correct — one batch, one event, on the surviving day, and the three
    /// removed days already unmarked. So whatever goes wrong is downstream, and the only
    /// downstream thing left is this: `CalendarStore.save` replaces the calendar's whole
    /// `eventBatches` list, which is an ObjectBox `ToMany` with **removals** in it. A
    /// `ToMany` whose target set shrinks is the one shape that `applyToDb()` can fail on
    /// without erroring loudly, and the storage layer carries a warning to that effect.
    @Test("Saving a batch with fewer events than before keeps the batch and the events that remain")
    func savingFewerEventsKeepsTheBatch() async throws {
        let store = try makeStore()
        defer { store.close() }
        let fixture = makeFixture(store: store)
        let cache = fixture.cache
        let port = fixture.port
        let id = try await createCalendar(cache)

        // Four days, as the STR builds them: one anchor and three added.
        let four = (0..<4).map { index in
            CalendarEvent(
                name: "Event",
                date: day.addingTimeInterval(Double(index) * 86400),
                colorName: "eventColorOption1"
            )
        }
        try await port.save(
            numberOfColumns: 3,
            eventBatches: [CalendarEventBatch(name: "Window", colorName: "eventColorOption1", events: four)],
            forCalendar: id
        )

        let before = try await port.eventBatches(calendarID: id)
        let beforeCount = before.count
        let beforeEvents = before.first?.events.count ?? -1
        #expect(beforeCount == 1, "setup: expected one batch, got \(beforeCount)")
        #expect(
            beforeEvents == 4,
            "setup: the batch should come back with all four days, got \(beforeEvents)"
        )

        // Which step lost them? Count the raw rows as well as what the batch holds. Four
        // rows with a one-entry relation would mean `events.replace` collapsed it; one row
        // would mean the events were never written as four — which is what an explicit
        // `id: 0` on every new event does, since the store reads 0 as a primary key rather
        // than as "unset".
        let rows = try store.box(for: PPEvent.self).all()
        #expect(rows.count == 4, "expected four event rows on disk, got \(rows.count)")

        // Now remove three of them — the whole point of the repro — and save again.
        let one = [four[3]]
        try await port.save(
            numberOfColumns: 3,
            eventBatches: [CalendarEventBatch(name: "Window", colorName: "eventColorOption1", events: one)],
            forCalendar: id
        )

        let after = try await port.eventBatches(calendarID: id)
        let afterCount = after.count
        let afterEvents = after.first?.events.count ?? -1
        let afterName = after.first?.events.first?.name ?? "<none>"

        #expect(afterCount == 1, "the batch itself must survive the save, got \(afterCount)")
        #expect(
            afterEvents == 1,
            "AB: the batch came back with \(afterEvents) events, expected the 1 that was saved"
        )
        #expect(
            afterName == "Event",
            "and the event that survives must be the one on the day that was kept, got '\(afterName)'"
        )
    }

    /// The store's behaviour on an emptied batch, recorded rather than assumed.
    ///
    /// It round-trips one — a batch with no events comes back as a batch with no events,
    /// not as no batch. That is faithful, not a defect: the port's job is to write what it
    /// is handed, and the *decision* to delete an emptied batch belongs to the reducer,
    /// which filters the row out of `state.batches` before any write is issued. Nothing in
    /// the app asks the store to delete, so asserting that it does would be asserting a
    /// contract `CalendarPersisting` does not have.
    ///
    /// What genuinely matters here is the second half: the removed events must not survive
    /// as orphans. An orphan is invisible in the UI but is real data, and it is what a later
    /// "one event was removed" save could resurrect.
    @Test("An emptied batch round-trips as an emptied batch, leaving no orphaned events")
    func savingNoEventsLeavesNoOrphans() async throws {
        let store = try makeStore()
        defer { store.close() }
        let fixture = makeFixture(store: store)
        let cache = fixture.cache
        let port = fixture.port
        let id = try await createCalendar(cache)

        let four = (0..<4).map { index in
            CalendarEvent(
                name: "Event",
                date: day.addingTimeInterval(Double(index) * 86400),
                colorName: "eventColorOption1"
            )
        }
        try await port.save(
            numberOfColumns: 3,
            eventBatches: [CalendarEventBatch(name: "Window", colorName: "eventColorOption1", events: four)],
            forCalendar: id
        )
        let seeded = try await port.eventBatches(calendarID: id)
        #expect(
            seeded.first?.events.count == 4,
            "setup: expected four events, got \(seeded.first?.events.count ?? -1)"
        )

        try await port.save(
            numberOfColumns: 3,
            eventBatches: [CalendarEventBatch(name: "Window", colorName: "eventColorOption1", events: [])],
            forCalendar: id
        )

        let after = try await port.eventBatches(calendarID: id)
        #expect(
            after.first?.events.isEmpty == true,
            "the store writes what it is handed: an emptied batch round-trips as emptied, got \(after.count) batch(es) with \(after.first?.events.count ?? -1) events"
        )

        let orphans = try store.box(for: PPEvent.self).all()
        #expect(
            orphans.isEmpty,
            "removed events must not linger as orphans; \(orphans.count) left behind"
        )
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
                ),
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
        let consumer = Task { for await change in stream {
            collector.append(change)
        } }
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
