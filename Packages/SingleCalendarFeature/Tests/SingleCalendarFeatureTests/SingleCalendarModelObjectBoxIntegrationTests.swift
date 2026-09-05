//
//  SingleCalendarModelObjectBoxIntegrationTests.swift
//  SingleCalendarFeatureTests
//
//  Tests exercising SingleCalendarModel flows against a real in-memory
//  ObjectBox store, verifying persistence via the model layer and directly
//  via ObjectBox boxes.
//

import Testing
import Foundation
import ObjectBox
import Combine
import DSKit
@testable import CorePersistence
@testable import SingleCalendarFeature

@MainActor
struct SingleCalendarModelObjectBoxIntegrationTests {

    // MARK: - Helpers

    private func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)!
    }

    private func event(_ name: String = "Event1", day: Int, color: String = "eventColorOption1", timestamp: UUID? = nil) -> EventDataSource {
        .init(name: name, date: date(year: 2026, month: 6, day: day), color: color, timestamp: timestamp)
    }

    private func makeStore() throws -> Store {
        try Store(directoryPath: "memory:model-integration-\(UUID().uuidString)")
    }

    private func makeCache(store: Store) -> CalendarCache {
        CalendarCache(repository: ObjectBoxCalendarStorage(store: store))
    }

    private func makeCalendar(in store: Store) -> PPCalendar {
        let calendar = PPCalendar(name: "Test", year: 2026, numberOfColumns: 3)
        try! store.box(for: PPCalendar.self).put(calendar)
        return calendar
    }

    private func waitForBatchCount(_ expected: Int, in store: Store, timeout: TimeInterval = 10) async throws -> Bool {
        let batchBox = store.box(for: PPEventBatch.self)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try batchBox.all().count >= expected { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return try batchBox.all().count >= expected
    }

    private func waitForStoreCondition(
        _ store: Store,
        timeout: TimeInterval = 10,
        _ check: @escaping () throws -> Bool
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try check() { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    /// Waits for the model to reflect a committed state. A committed batch is
    /// written to the store asynchronously, and the resulting cache change can
    /// race with the model's own synchronous update — so a direct read right
    /// after `commitPendingBatch` may briefly see stale `originalBatches`.
    @MainActor
    private func waitForModelCondition(
        _ model: SingleCalendarModel,
        timeout: TimeInterval = 10,
        _ check: @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if check() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return check()
    }

    // MARK: - Batch persistence via SingleCalendarModel + direct ObjectBox verification

    @Test func commitBatchPersistsViaModelAndVerifiableInStorage() async throws {
        let store = try makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let cache = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)
        #expect(model.state == .content)

        model.selectedColor = .option1
        model.changeEvent(event(day: 10))
        model.changeEvent(event(day: 11))
        model.daySelectionManager.selectionMode = .multiple

        model.prepareAddEditEventBatchViewModel()
        let addEdit = model.makeBatchEditor()
        addEdit.eventBatchName = "Women Cycle"
        addEdit.selectedColor = .option1
        addEdit.recolorAllEvents()

        #expect(addEdit.save())
        model.commitPendingBatch(addEdit.eventBatch)
        #expect(try await waitForBatchCount(1, in: store))

        // Path A: verify via model
        #expect(await waitForModelCondition(model) { model.hasEvents(on: date(year: 2026, month: 6, day: 10)) })
        #expect(await waitForModelCondition(model) { model.hasEvents(on: date(year: 2026, month: 6, day: 11)) })

        // Path B: verify via direct ObjectBox
        let batchBox = store.box(for: PPEventBatch.self)
        let eventBox = store.box(for: PPEvent.self)
        let batches = try batchBox.all()
        #expect(batches.count == 1)
        #expect(batches[0].title == "Women Cycle")
        #expect(batches[0].color == "eventColorOption1")
        let events = try eventBox.all()
        #expect(events.count == 2)
        #expect(events.contains(where: { $0.name == "Event1" }))
    }

    @Test func editBatchNamePersistsViaModelAndVerifiableInStorage() async throws {
        let store = try makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let day10 = date(year: 2026, month: 6, day: 10)

        let batch = PPEventBatch(title: "Original Name", color: "eventColorOption1")
        let batchBox = store.box(for: PPEventBatch.self)
        try batchBox.put(batch)
        let events = [
            PPEvent(name: "Event1", color: "eventColorOption1", date: day10)
        ]
        let eventBox = store.box(for: PPEvent.self)
        try eventBox.put(events)
        batch.events.replace(events)
        try batch.events.applyToDb()
        let savedCalendar = try store.box(for: PPCalendar.self).get(ppCalendar.id)!
        savedCalendar.eventBatches.append(batch)
        try savedCalendar.eventBatches.applyToDb()

        let cache = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)
        let batchList = model.batches(for: day10)
        let addEdit = model.makeBatchEditor()

        addEdit.load(batchList[0])
        addEdit.eventBatchName = "Renamed"
        #expect(addEdit.save())
        model.commitPendingBatch(addEdit.eventBatch)

        // Wait for async save to persist the renamed batch
        #expect(try await waitForStoreCondition(store) {
            try batchBox.all().first?.title == "Renamed"
        })

        // Path A: verify via model
        #expect(await waitForModelCondition(model) { model.hasEvents(on: day10) })

        // Path B: verify via direct ObjectBox
        let persisted = try batchBox.all()[0]
        #expect(persisted.title == "Renamed")
    }

    @Test func savingInEditorCommitsWithoutReachingNavigationRoot() async throws {
        let store = try makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let day10 = date(year: 2026, month: 6, day: 10)
        let day15 = date(year: 2026, month: 6, day: 15)

        let batch = PPEventBatch(title: "Original Name", color: "eventColorOption1")
        let batchBox = store.box(for: PPEventBatch.self)
        try batchBox.put(batch)
        let events = [
            PPEvent(name: "Event1", color: "eventColorOption1", date: day10)
        ]
        let eventBox = store.box(for: PPEvent.self)
        try eventBox.put(events)
        batch.events.replace(events)
        try batch.events.applyToDb()
        let savedCalendar = try store.box(for: PPCalendar.self).get(ppCalendar.id)!
        savedCalendar.eventBatches.append(batch)
        try savedCalendar.eventBatches.applyToDb()

        let cache = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)
        #expect(await waitForModelCondition(model) { !model.hasEvents(on: day15) })

        // STR: tap day -> batch list -> tap batch -> editor
        let batchList = model.batches(for: day10)
        let addEdit = model.makeBatchEditor()

        // Select an additional event and press Save (commit happens on save,
        // not when the navigation stack reaches its root).
        addEdit.load(batchList[0])
        addEdit.toggleEvent(on: day15)
        #expect(addEdit.save())
        model.commitPendingBatch(addEdit.eventBatch)

        // Path A: UI shows the new day immediately after Save + Back.
        #expect(await waitForModelCondition(model) { model.hasEvents(on: day15) })
        #expect(await waitForModelCondition(model) { model.hasEvents(on: day10) })
        #expect(model.batches(for: day10)[0].events.count == 2)

        // Path B: exactly one batch with two events is persisted (no duplicates).
        #expect(try await waitForStoreCondition(store) {
            let batchCount = try batchBox.all().count
            let eventCount = try eventBox.all().count
            return batchCount == 1 && eventCount == 2
        })
        #expect(try batchBox.all().count == 1)
        #expect(try eventBox.all().count == 2)

        // Idempotency: later pop to root (resetSelectedDays) must not duplicate.
        model.resetSelectedDays()
        #expect(try await waitForStoreCondition(store) {
            let batchCount = try batchBox.all().count
            let eventCount = try eventBox.all().count
            return batchCount == 1 && eventCount == 2
        })
        #expect(try batchBox.all().count == 1)
        #expect(try eventBox.all().count == 2)
    }

    @Test func deleteBatchPersistsViaModelAndVerifiableInStorage() async throws {
        let store = try makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let day10 = date(year: 2026, month: 6, day: 10)

        let batch = PPEventBatch(title: "To Delete", color: "eventColorOption1")
        let batchBox = store.box(for: PPEventBatch.self)
        try batchBox.put(batch)
        let events = [
            PPEvent(name: "Event1", color: "eventColorOption1", date: day10)
        ]
        let eventBox = store.box(for: PPEvent.self)
        try eventBox.put(events)
        batch.events.replace(events)
        try batch.events.applyToDb()
        let savedCalendar = try store.box(for: PPCalendar.self).get(ppCalendar.id)!
        savedCalendar.eventBatches.append(batch)
        try savedCalendar.eventBatches.applyToDb()

        let cache = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)

        let batchDataSource = EventBatchDataSource(
            id: Int64(batch.id),
            name: "To Delete",
            colorName: "eventColorOption1",
            events: [],
            date: day10
        )
        model.deleteBatches([batchDataSource], for: Int64(ppCalendar.id))

        // Wait for async save to persist the deletion
        #expect(try await waitForStoreCondition(store) {
            try batchBox.all().isEmpty
        })

        // Path A: verify via model
        #expect(await waitForModelCondition(model) { !model.hasEvents(on: day10) })

        // Path B: verify via direct ObjectBox
        let persisted = try batchBox.all()
        #expect(persisted.isEmpty)
        let persistedEvents = try eventBox.all()
        #expect(persistedEvents.isEmpty)
    }

    @Test func addEventToBatchPersistsViaModelAndVerifiableInStorage() async throws {
        let store = try makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let cache = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)

        model.selectedColor = .option1
        model.changeEvent(event(day: 10))
        model.changeEvent(event(day: 11))
        model.changeEvent(event(day: 12))
        model.daySelectionManager.selectionMode = .multiple

        model.prepareAddEditEventBatchViewModel()
        let addEdit = model.makeBatchEditor()
        addEdit.eventBatchName = "Three Events"
        addEdit.selectedColor = .option1
        addEdit.recolorAllEvents()
        #expect(addEdit.save())
        model.commitPendingBatch(addEdit.eventBatch)
        #expect(try await waitForBatchCount(1, in: store))

        // Path A: verify via model
        #expect(await waitForModelCondition(model) { model.hasEvents(on: date(year: 2026, month: 6, day: 10)) })
        #expect(await waitForModelCondition(model) { model.hasEvents(on: date(year: 2026, month: 6, day: 11)) })
        #expect(await waitForModelCondition(model) { model.hasEvents(on: date(year: 2026, month: 6, day: 12)) })

        // Path B: verify via direct ObjectBox
        let eventBox = store.box(for: PPEvent.self)
        let events = try eventBox.all()
        #expect(events.count == 3)
        let sortedEvents = events.sorted { $0.date < $1.date }
        #expect(sortedEvents[0].name == "Event1")
        #expect(sortedEvents[0].color == "eventColorOption1")
        #expect(Calendar.current.isDate(sortedEvents[0].date, inSameDayAs: date(year: 2026, month: 6, day: 10)))
    }

    @Test func removeEventsFromBatchPersistsViaModelAndVerifiableInStorage() async throws {
        let store = try makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let day10 = date(year: 2026, month: 6, day: 10)
        let day12 = date(year: 2026, month: 6, day: 12)

        let batch = PPEventBatch(title: "Cycle", color: "eventColorOption1")
        let batchBox = store.box(for: PPEventBatch.self)
        try batchBox.put(batch)
        let ppEvents = [
            PPEvent(name: "Event1", color: "eventColorOption1", date: day10),
            PPEvent(name: "Event1", color: "eventColorOption1", date: day12)
        ]
        let eventBox = store.box(for: PPEvent.self)
        try eventBox.put(ppEvents)
        batch.events.replace(ppEvents)
        try batch.events.applyToDb()
        let savedCalendar = try store.box(for: PPCalendar.self).get(ppCalendar.id)!
        savedCalendar.eventBatches.append(batch)
        try savedCalendar.eventBatches.applyToDb()

        let cache = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)
        let batchList = model.batches(for: day10)
        let addEdit = model.makeBatchEditor()

        addEdit.load(batchList[0])
        addEdit.toggleEvent(on: day12) // Remove day12 event
        #expect(addEdit.save())
        model.commitPendingBatch(addEdit.eventBatch)

        // Wait for async save to persist the event removal
        #expect(try await waitForStoreCondition(store) {
            try eventBox.all().count == 1
        })

        // Path A: verify via model
        #expect(await waitForModelCondition(model) { model.hasEvents(on: day10) })
        #expect(await waitForModelCondition(model) { !model.hasEvents(on: day12) })

        // Path B: verify via direct ObjectBox
        let persistedEvents = try eventBox.all()
        #expect(persistedEvents.count == 1)
        #expect(Calendar.current.isDate(persistedEvents[0].date, inSameDayAs: day10))
    }

    @Test func batchUpdateWithNewColorPersistsViaModelAndVerifiableInStorage() async throws {
        let store = try makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let day10 = date(year: 2026, month: 6, day: 10)

        let batch = PPEventBatch(title: "Cycle", color: "eventColorOption1")
        let batchBox = store.box(for: PPEventBatch.self)
        try batchBox.put(batch)
        let ppEvents = [
            PPEvent(name: "Event1", color: "eventColorOption1", date: day10)
        ]
        let eventBox = store.box(for: PPEvent.self)
        try eventBox.put(ppEvents)
        batch.events.replace(ppEvents)
        try batch.events.applyToDb()
        let savedCalendar = try store.box(for: PPCalendar.self).get(ppCalendar.id)!
        savedCalendar.eventBatches.append(batch)
        try savedCalendar.eventBatches.applyToDb()

        let cache = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)
        let batchList = model.batches(for: day10)
        let addEdit = model.makeBatchEditor()

        addEdit.load(batchList[0])
        addEdit.selectedColor = .option3
        addEdit.recolorAllEvents()
        #expect(addEdit.save())
        model.commitPendingBatch(addEdit.eventBatch)

        // Wait for async save to persist the color change
        #expect(try await waitForStoreCondition(store) {
            try batchBox.all().first?.color == "eventColorOption3"
        })

        // Path A: verify via model
        #expect(await waitForModelCondition(model) { model.hasEvents(on: day10) })

        // Path B: verify via direct ObjectBox
        let persisted = try batchBox.all()[0]
        #expect(persisted.color == "eventColorOption3")
        let persistedEvents = Array(persisted.events)
        #expect(persistedEvents.count == 1)
        #expect(persistedEvents[0].color == "eventColorOption3")
    }

    @Test func twoIndependentBatchesBothPersistViaModelAndVerifiableInStorage() async throws {
        let store = try makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let cache = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)

        // Create batch A
        model.selectedColor = .option1
        model.changeEvent(event(day: 10))
        model.daySelectionManager.selectionMode = .multiple
        model.prepareAddEditEventBatchViewModel()
        let addEditA = model.makeBatchEditor()
        addEditA.eventBatchName = "Batch A"
        addEditA.selectedColor = .option1
        addEditA.recolorAllEvents()
        #expect(addEditA.save())
        model.commitPendingBatch(addEditA.eventBatch)
        #expect(try await waitForBatchCount(1, in: store))

        // Create batch B
        model.selectedColor = .option3
        model.changeEvent(event(day: 20))
        model.daySelectionManager.selectionMode = .multiple
        model.prepareAddEditEventBatchViewModel()
        let addEditB = model.makeBatchEditor()
        addEditB.eventBatchName = "Batch B"
        addEditB.selectedColor = .option3
        addEditB.recolorAllEvents()
        #expect(addEditB.save())
        model.commitPendingBatch(addEditB.eventBatch)
        #expect(try await waitForBatchCount(2, in: store))

        // Path A: verify via model
        #expect(await waitForModelCondition(model) { model.hasEvents(on: date(year: 2026, month: 6, day: 10)) })
        #expect(await waitForModelCondition(model) { model.hasEvents(on: date(year: 2026, month: 6, day: 20)) })

        // Path B: verify via direct ObjectBox
        let batchBox = store.box(for: PPEventBatch.self)
        let batches = try batchBox.all()
        #expect(batches.count == 2)
        let names = Set(batches.map(\.title))
        #expect(names.contains("Batch A"))
        #expect(names.contains("Batch B"))
    }

    @Test func calendarUpdateAfterBatchCommitRetrievesCorrectBatchesViaCache() async throws {
        let store = try makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let cache = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)

        model.selectedColor = .option1
        model.changeEvent(event(day: 10))
        model.daySelectionManager.selectionMode = .multiple
        model.prepareAddEditEventBatchViewModel()
        let addEdit = model.makeBatchEditor()
        addEdit.eventBatchName = "Persisted"
        addEdit.selectedColor = .option1
        addEdit.recolorAllEvents()
        #expect(addEdit.save())
        model.commitPendingBatch(addEdit.eventBatch)
        #expect(try await waitForBatchCount(1, in: store))

        // Path A: verify via cache
        let fromCache = try await cache.getCalendar(id: Int64(ppCalendar.id))
        #expect(fromCache != nil)
        #expect(fromCache?.eventBatches.count == 1)
        #expect(fromCache?.eventBatches.first?.name == "Persisted")
        #expect(fromCache?.eventBatches.first?.events.count == 1)

        // Path B: verify via direct ObjectBox
        let calendarBox = store.box(for: PPCalendar.self)
        let batchBox = store.box(for: PPEventBatch.self)
        let persistedCalendar = try calendarBox.get(ppCalendar.id)
        #expect(persistedCalendar != nil)
        #expect(persistedCalendar?.eventBatches.count == 1)
        let persistedBatch = try batchBox.all()[0]
        #expect(persistedBatch.title == "Persisted")
        #expect(Array(persistedBatch.events).count == 1)
    }

    // MARK: - Event add/edit/remove via SingleCalendarModel + direct ObjectBox verification

    @Test func addEventWithCustomColorPersistsViaModelAndVerifiableInStorage() async throws {
        let store = try makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let cache = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)

        model.selectedColor = .option3
        model.changeEvent(event(day: 10, color: "eventColorOption3"))
        model.daySelectionManager.selectionMode = .multiple

        model.prepareAddEditEventBatchViewModel()
        let addEdit = model.makeBatchEditor()
        addEdit.eventBatchName = "Custom Color"
        addEdit.selectedColor = .option3
        addEdit.recolorAllEvents()
        #expect(addEdit.save())
        model.commitPendingBatch(addEdit.eventBatch)
        #expect(try await waitForBatchCount(1, in: store))

        // Path A: verify via model
        #expect(await waitForModelCondition(model) { model.hasEvents(on: date(year: 2026, month: 6, day: 10)) })

        // Path B: verify via direct ObjectBox
        let eventBox = store.box(for: PPEvent.self)
        let events = try eventBox.all()
        #expect(events.count == 1)
        #expect(events[0].color == "eventColorOption3")
    }

    @Test func editEventColorInBatchPersistsViaModelAndVerifiableInStorage() async throws {
        let store = try makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let day10 = date(year: 2026, month: 6, day: 10)

        let batch = PPEventBatch(title: "Cycle", color: "eventColorOption1")
        let batchBox = store.box(for: PPEventBatch.self)
        try batchBox.put(batch)
        let ppEvents = [
            PPEvent(name: "Event1", color: "eventColorOption1", date: day10)
        ]
        try store.box(for: PPEvent.self).put(ppEvents)
        batch.events.replace(ppEvents)
        try batch.events.applyToDb()
        let savedCalendar = try store.box(for: PPCalendar.self).get(ppCalendar.id)!
        savedCalendar.eventBatches.append(batch)
        try savedCalendar.eventBatches.applyToDb()

        let cache = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)
        let batchList = model.batches(for: day10)
        let addEdit = model.makeBatchEditor()

        addEdit.load(batchList[0])
        let first = addEdit.eventsSelectionManager.events[0]
        let editor = AddEditEventViewModel()
        editor.update(from: first)
        editor.selectedColor = .option2
        #expect(editor.save())
        addEdit.eventsSelectionManager.apply(editor.event!)
        #expect(addEdit.save())
        model.commitPendingBatch(addEdit.eventBatch)

        let eventBox = store.box(for: PPEvent.self)

        // Wait for async save to persist the event color change
        #expect(try await waitForStoreCondition(store) {
            try eventBox.all().first?.color == "eventColorOption2"
        })

        // Path A: verify via model
        #expect(await waitForModelCondition(model) { model.hasEvents(on: day10) })

        // Path B: verify via direct ObjectBox
        let events = try eventBox.all()
        #expect(events.count == 1)
        #expect(events[0].color == "eventColorOption2")
    }

    @Test func removeAllEventsFromBatchDeletesBatchAndEvents() async throws {
        let store = try makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let day10 = date(year: 2026, month: 6, day: 10)

        let batch = PPEventBatch(title: "To Clear", color: "eventColorOption1")
        let batchBox = store.box(for: PPEventBatch.self)
        try batchBox.put(batch)
        let ppEvents = [
            PPEvent(name: "Event1", color: "eventColorOption1", date: day10)
        ]
        let eventBox = store.box(for: PPEvent.self)
        try eventBox.put(ppEvents)
        batch.events.replace(ppEvents)
        try batch.events.applyToDb()
        let savedCalendar = try store.box(for: PPCalendar.self).get(ppCalendar.id)!
        savedCalendar.eventBatches.append(batch)
        try savedCalendar.eventBatches.applyToDb()

        let cache = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)
        let batchList = model.batches(for: day10)
        let addEdit = model.makeBatchEditor()

        addEdit.load(batchList[0])
        addEdit.toggleEvent(on: day10) // Remove all events
        #expect(addEdit.save())
        model.commitPendingBatch(addEdit.eventBatch)

        // Wait for async save to persist the deletion
        #expect(try await waitForStoreCondition(store) {
            try batchBox.all().isEmpty
        })

        // Path A: verify via model
        #expect(await waitForModelCondition(model) { !model.hasEvents(on: day10) })

        // Path B: verify via direct ObjectBox
        let persistedBatches = try batchBox.all()
        #expect(persistedBatches.isEmpty)
        let persistedEvents = try eventBox.all()
        #expect(persistedEvents.isEmpty)
    }

    @Test func createMultipleBatchesOnDifferentDaysPersistsCorrectly() async throws {
        let store = try makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let cache = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)

        let day5 = date(year: 2026, month: 6, day: 5)
        let day15 = date(year: 2026, month: 6, day: 15)

        // Batch on day 5
        model.selectedColor = .option1
        model.changeEvent(EventDataSource(name: "Day5 Event", date: day5, color: PCColorOption.option1.colorName))
        model.daySelectionManager.selectionMode = .multiple
        model.prepareAddEditEventBatchViewModel()
        let addEditA = model.makeBatchEditor()
        addEditA.eventBatchName = "Day 5 Batch"
        addEditA.selectedColor = .option1
        addEditA.recolorAllEvents()
        #expect(addEditA.save())
        model.commitPendingBatch(addEditA.eventBatch)
        #expect(try await waitForBatchCount(1, in: store))

        // Batch on day 15
        model.selectedColor = .option4
        model.changeEvent(EventDataSource(name: "Day15 Event", date: day15, color: PCColorOption.option4.colorName))
        model.daySelectionManager.selectionMode = .multiple
        model.prepareAddEditEventBatchViewModel()
        let addEditB = model.makeBatchEditor()
        addEditB.eventBatchName = "Day 15 Batch"
        addEditB.selectedColor = .option4
        addEditB.recolorAllEvents()
        #expect(addEditB.save())
        model.commitPendingBatch(addEditB.eventBatch)
        #expect(try await waitForBatchCount(2, in: store))

        // Path A: verify via model
        #expect(await waitForModelCondition(model) { model.hasEvents(on: day5) })
        #expect(await waitForModelCondition(model) { model.hasEvents(on: day15) })

        // Path B: verify via direct ObjectBox
        let batchBox = store.box(for: PPEventBatch.self)
        let batches = try batchBox.all()
        #expect(batches.count == 2)

        let day5Batch = batches.first(where: { $0.title == "Day 5 Batch" })
        #expect(day5Batch != nil)
        #expect(day5Batch?.color == "eventColorOption1")
        let day5Events = Array(day5Batch!.events)
        #expect(day5Events.count == 1)
        #expect(Calendar.current.isDate(day5Events[0].date, inSameDayAs: day5))

        let day15Batch = batches.first(where: { $0.title == "Day 15 Batch" })
        #expect(day15Batch != nil)
        #expect(day15Batch?.color == "eventColorOption4")
        let day15Events = Array(day15Batch!.events)
        #expect(day15Events.count == 1)
        #expect(Calendar.current.isDate(day15Events[0].date, inSameDayAs: day15))
    }

    // MARK: - Batch persistence via save(for:) round-trip

    @Test func saveForCalendarRoundTripsBatchDataThroughCache() async throws {
        let store = try makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let cache = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)

        // Create and commit batch
        model.selectedColor = .option1
        model.changeEvent(event(day: 10))
        model.daySelectionManager.selectionMode = .multiple
        model.prepareAddEditEventBatchViewModel()
        let addEdit = model.makeBatchEditor()
        addEdit.eventBatchName = "Round Trip"
        addEdit.selectedColor = .option1
        addEdit.recolorAllEvents()
        #expect(addEdit.save())
        model.commitPendingBatch(addEdit.eventBatch)
        #expect(try await waitForBatchCount(1, in: store))

        // Re-fetch from cache to verify round-trip
        let freshCache = {
            let storage = ObjectBoxCalendarStorage(store: store)
            return CalendarCache(repository: storage)
        }()
        let calendar = try await freshCache.getCalendar(id: Int64(ppCalendar.id))
        #expect(calendar?.eventBatches.count == 1)
        #expect(calendar?.eventBatches.first?.name == "Round Trip")
        #expect(calendar?.eventBatches.first?.events.count == 1)

        // Path B: verify via direct ObjectBox
        let batchBox = store.box(for: PPEventBatch.self)
        let eventBox = store.box(for: PPEvent.self)
        #expect(try batchBox.all().count == 1)
        #expect(try eventBox.all().count == 1)
        #expect(try eventBox.all()[0].name == "Event1")
    }

    @Test func editBatchThenFetchReturnsUpdatedData() async throws {
        let store = try makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let day10 = date(year: 2026, month: 6, day: 10)
        let day15 = date(year: 2026, month: 6, day: 15)

        let batch = PPEventBatch(title: "Original", color: "eventColorOption1")
        let batchBox = store.box(for: PPEventBatch.self)
        try batchBox.put(batch)
        let ppEvents = [
            PPEvent(name: "Event1", color: "eventColorOption1", date: day10),
            PPEvent(name: "Event2", color: "eventColorOption1", date: day15)
        ]
        let eventBox = store.box(for: PPEvent.self)
        try eventBox.put(ppEvents)
        batch.events.replace(ppEvents)
        try batch.events.applyToDb()
        let savedCalendar = try store.box(for: PPCalendar.self).get(ppCalendar.id)!
        savedCalendar.eventBatches.append(batch)
        try savedCalendar.eventBatches.applyToDb()

        let cache = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)

        // Edit batch: remove day15 event, rename
        let batchList = model.batches(for: day10)
        let addEdit = model.makeBatchEditor()

        addEdit.load(batchList[0])
        addEdit.eventBatchName = "Edited"
        addEdit.toggleEvent(on: day15) // Remove day15
        #expect(addEdit.save())
        model.commitPendingBatch(addEdit.eventBatch)

        // Wait for async save to persist the edited batch
        #expect(try await waitForStoreCondition(store) {
            try batchBox.all().first?.title == "Edited"
        })

        // Verify via cache
        let fromCache = try await cache.getCalendar(id: Int64(ppCalendar.id))
        #expect(fromCache?.eventBatches.count == 1)
        #expect(fromCache?.eventBatches.first?.name == "Edited")
        #expect(fromCache?.eventBatches.first?.events.count == 1)

        // Verify via direct ObjectBox
        let persistedBatch = try batchBox.all()[0]
        #expect(persistedBatch.title == "Edited")
        #expect(Array(persistedBatch.events).count == 1)
        let persistedEvent = Array(persistedBatch.events)[0]
        #expect(Calendar.current.isDate(persistedEvent.date, inSameDayAs: day10))
    }

    // MARK: - Batch list refresh after editing the anchor day

    @Test func editingBatchKeepsItInBatchListAfterRemovingAnchorDay() async throws {
        let store = try makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let cache = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)
        #expect(model.state == .content)

        let day10 = date(year: 2026, month: 4, day: 10)
        let day11 = date(year: 2026, month: 4, day: 11)
        let day12 = date(year: 2026, month: 4, day: 12)

        // STR 2-4: tap empty day 10 -> editor anchored at day 10, add 11 & 12.
        model.prepareAddEditEventBatchViewModel(for: day10)
        let addEdit = model.makeBatchEditor()
        addEdit.eventBatchName = "Batch"
        addEdit.selectedColor = .option1
        addEdit.toggleEvent(on: day11)
        addEdit.toggleEvent(on: day12)
        #expect(addEdit.save())
        model.commitPendingBatch(addEdit.eventBatch)
        #expect(try await waitForBatchCount(1, in: store))
        try? await Task.sleep(for: .milliseconds(300))

        // STR 6: day 10 list must contain the batch.
        #expect(model.batches(for: day10).count == 1,
                "Day 10 list should contain the batch right after creation")

        // STR 7-8: open the batch, remove day 10.
        let batchList = model.batches(for: day10)
        let addEdit2 = model.makeBatchEditor()
        addEdit2.load(batchList[0])
        addEdit2.toggleEvent(on: day10)
        #expect(addEdit2.eventsSelectionManager.events.contains {
            Calendar.current.isDate($0.date, inSameDayAs: day10)
        } == false, "day 10 event must be removed")

        // STR 9: save.
        #expect(addEdit2.save())
        model.commitPendingBatch(addEdit.eventBatch)
        try? await Task.sleep(for: .milliseconds(300))

        // The batch still has 11 & 12, so the day-10 batch list must not be empty.
        #expect(model.batches(for: day10).count == 1,
                "Batch list should still contain the batch (events remain on 11 & 12)")
    }

    @Test func removingAnchorDayFromNilDateBatchKeepsItInBatchList() async throws {
        let store = try makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let cache = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)
        #expect(model.state == .content)

        let day10 = date(year: 2026, month: 4, day: 10)
        let day11 = date(year: 2026, month: 4, day: 11)
        let day12 = date(year: 2026, month: 4, day: 12)

        // Create a batch through the multiselect path — this leaves its
        // `date` (anchor) nil, so the batch is only associated with its events.
        model.selectedColor = .option1
        model.changeEvent(EventDataSource(name: "", date: day10, color: PCColorOption.option1.colorName))
        model.changeEvent(EventDataSource(name: "", date: day11, color: PCColorOption.option1.colorName))
        model.changeEvent(EventDataSource(name: "", date: day12, color: PCColorOption.option1.colorName))
        model.daySelectionManager.selectionMode = .multiple
        _ = model.handleSelectionConfirmation()

        let addEdit = model.makeBatchEditor()
        addEdit.eventBatchName = "Batch"
        addEdit.selectedColor = .option1
        #expect(addEdit.save())
        model.commitPendingBatch(addEdit.eventBatch)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(model.batches(for: day10).count == 1,
                "Day 10 list should contain the batch right after creation")

        // Open the batch, remove day 10.
        let listVM = AddEditEventBatchListViewModel(
            eventsSelectionManager: model.eventsSelectionManager,
            daySelectionManager: model.daySelectionManager
        )
        listVM.prepare(with: model.batches(for: day10), and: day10)
        let batchList = model.batches(for: day10)
        let addEdit2 = model.makeBatchEditor()
        addEdit2.load(batchList[0])
        addEdit2.toggleEvent(on: day10)
        #expect(addEdit2.save())
        model.commitPendingBatch(addEdit2.eventBatch)

        // The visible batch list keeps the just-saved batch even though it no
        // longer falls on day 10.
        #expect(listVM.eventBatches.count == 1,
                "Batch list should still contain the batch (events remain on 11 & 12)")
    }

    // MARK: - Year view markers must reflect actual events

    @Test func removingAnchorDayUncolorsItOnYearView() async throws {
        let store = try makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let cache = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)
        #expect(model.state == .content)

        let day10 = date(year: 2026, month: 4, day: 10)
        let day11 = date(year: 2026, month: 4, day: 11)
        let day12 = date(year: 2026, month: 4, day: 12)

        // Create a batch anchored at day 10, with events on 11 & 12.
        model.prepareAddEditEventBatchViewModel(for: day10)
        let addEdit = model.makeBatchEditor()
        addEdit.load(nil, selectedDay: day10)
        addEdit.eventBatchName = "Batch"
        addEdit.selectedColor = .option1
        addEdit.toggleEvent(on: day11)
        addEdit.toggleEvent(on: day12)
        #expect(addEdit.save())
        model.commitPendingBatch(addEdit.eventBatch)
        try? await Task.sleep(for: .milliseconds(300))

        // The anchor day is marked right after creation (it has an event).
        #expect(!dayMarkers(model, day10).isEmpty,
                "Day 10 should be marked after creation")

        // Open the batch and remove day 10.
        let batchList = model.batches(for: day10)
        let addEdit2 = model.makeBatchEditor()
        addEdit2.load(batchList[0])
        addEdit2.toggleEvent(on: day10)
        #expect(addEdit2.save())
        model.commitPendingBatch(addEdit2.eventBatch)
        try? await Task.sleep(for: .milliseconds(300))

        // The marker must be driven by events: day 10 is unmarked, 11 & 12 stay.
        #expect(dayMarkers(model, day10).isEmpty,
                "Day 10 must NOT be marked after its event was removed from the batch")
        #expect(!dayMarkers(model, day11).isEmpty,
                "Day 11 should still be marked")
        #expect(!dayMarkers(model, day12).isEmpty,
                "Day 12 should still be marked")
    }

    private func dayMarkers(_ model: SingleCalendarModel, _ date: Date) -> [String] {
        for month in model.yearModel.months {
            for week in month.weeks {
                for day in week.days {
                    guard let d = day.date, day.isInCurrentMonth,
                          Calendar.current.isDate(d, inSameDayAs: date) else { continue }
                    return day.events
                }
            }
        }
        return []
    }
}