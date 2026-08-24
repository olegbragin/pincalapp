//
//  CalendarCacheIntegrationTests.swift
//  PinCalAppTests
//
//  Created by Oleg Bragin on 23.08.2026.
//

import Testing
import Foundation
import ObjectBox
import Combine
@testable import PinCalApp

@MainActor
struct CalendarCacheIntegrationTests {

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

    private func makeStore() -> Store {
        try! Store(directoryPath: "memory:cache-integration-\(UUID().uuidString)")
    }

    private func makeCache(store: Store) -> (CalendarCache, CalendarManager) {
        let manager = CalendarManager(service: ObjectBoxCalendarStorage(store: store))
        let cache = CalendarCache(manager: manager)
        return (cache, manager)
    }

    private func makeCalendar(in store: Store) -> PPCalendar {
        let calendar = PPCalendar(name: "Test", year: 2026, numberOfColumns: 3)
        try! store.box(for: PPCalendar.self).put(calendar)
        return calendar
    }

    private func waitForBatchCount(_ expected: Int, in store: Store, timeout: TimeInterval = 3) async throws -> Bool {
        let batchBox = store.box(for: PPEventBatch.self)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try batchBox.all().count >= expected { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return try batchBox.all().count >= expected
    }

    private func waitForCondition(_ check: () -> Bool, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !check(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - Calendar CRUD via CalendarCache + direct ObjectBox verification

    @Test func createCalendarPersistsViaCache() async throws {
        let store = makeStore()
        defer { store.close() }

        let (cache, _) = makeCache(store: store)
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
        let store = makeStore()
        defer { store.close() }

        let (cache, _) = makeCache(store: store)
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
        let store = makeStore()
        defer { store.close() }

        let (cache, _) = makeCache(store: store)
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
        let store = makeStore()
        defer { store.close() }

        let (cache, _) = makeCache(store: store)
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
        let store = makeStore()
        defer { store.close() }

        let (cache, _) = makeCache(store: store)
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
        let store = makeStore()
        defer { store.close() }

        let (cache, _) = makeCache(store: store)
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
        let store = makeStore()
        defer { store.close() }

        let (cache, _) = makeCache(store: store)

        let cal1 = try await cache.createCalendar(name: "Active1", year: 2026, numberOfColumns: 2)
        let cal2 = try await cache.createCalendar(name: "Active2", year: 2026, numberOfColumns: 3)
        _ = try await cache.createCalendar(name: "Archived", year: 2026, numberOfColumns: 4)

        try await cache.archiveCalendar(try await cache.getCalendar(id: cal2.id) ?? cal1)

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
        #expect(active.count == 1)
        #expect(active[0].name == "Active1")
    }

    @Test func loadArchivedReturnsOnlyArchivedViaCache() async throws {
        let store = makeStore()
        defer { store.close() }

        let (cache, _) = makeCache(store: store)

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

    // MARK: - Event Batch persistence via SingleCalendarModel + direct ObjectBox verification

    @Test func commitBatchPersistsViaModelAndVerifiableInStorage() async throws {
        let store = makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let (cache, _) = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)
        #expect(model.state == .content)

        model.selectedColor = .option1
        model.changeEvent(event(day: 10))
        model.changeEvent(event(day: 11))
        model.daySelectionManager.selectionMode = .multiple

        model.prepareAddEditEventBatchViewModel()
        let addEdit = model.addEditBatchListViewModel.addEditEventBatchModel
        addEdit.eventBatchName = "Women Cycle"
        addEdit.selectedColor = .option1
        addEdit.recolorAllEvents()

        #expect(addEdit.save())
        model.resetSelectedDays()

        #expect(try await waitForBatchCount(1, in: store))

        // Path A: verify via model
        #expect(model.hasEvents(on: date(year: 2026, month: 6, day: 10)))
        #expect(model.hasEvents(on: date(year: 2026, month: 6, day: 11)))

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
        let store = makeStore()
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

        let (cache, _) = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)

        model.prepareAddEditBatchListViewModel(with: [day10])
        let batchList = model.addEditBatchListViewModel
        batchList.prepareAddEditBatchViewModel(with: batchList.eventBatches[0])

        let addEdit = batchList.addEditEventBatchModel
        addEdit.eventBatchName = "Renamed"
        #expect(addEdit.save())
        model.resetSelectedDays()

        #expect(try await waitForBatchCount(1, in: store))

        // Path A: verify via model
        #expect(model.hasEvents(on: day10))

        // Path B: verify via direct ObjectBox
        let persisted = try batchBox.all()[0]
        #expect(persisted.title == "Renamed")
    }

    @Test func savingInEditorCommitsWithoutReachingNavigationRoot() async throws {
        let store = makeStore()
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

        let (cache, _) = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)
        #expect(!model.hasEvents(on: day15))

        // STR: tap day -> batch list -> tap batch -> editor
        model.prepareAddEditBatchListViewModel(with: [day10])
        let batchList = model.addEditBatchListViewModel
        batchList.prepareAddEditBatchViewModel(with: batchList.eventBatches[0])

        // Select an additional event and press Save (commit happens on save,
        // not when the navigation stack reaches its root).
        let addEdit = batchList.addEditEventBatchModel
        addEdit.toggleEvent(on: day15)
        #expect(addEdit.save())
        model.commitPendingBatch()

        // Path A: UI shows the new day immediately after Save + Back.
        #expect(model.hasEvents(on: day15))
        #expect(model.hasEvents(on: day10))
        #expect(batchList.eventBatches[0].events.count == 2)

        // Path B: exactly one batch with two events is persisted (no duplicates).
        #expect(try await waitForBatchCount(1, in: store))
        try await Task.sleep(for: .milliseconds(300))
        #expect(try batchBox.all().count == 1)
        #expect(try eventBox.all().count == 2)

        // Idempotency: later pop to root (resetSelectedDays) must not duplicate.
        model.resetSelectedDays()
        try await Task.sleep(for: .milliseconds(300))
        #expect(try batchBox.all().count == 1)
        #expect(try eventBox.all().count == 2)
    }

    @Test func deleteBatchPersistsViaModelAndVerifiableInStorage() async throws {
        let store = makeStore()
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

        let (cache, _) = makeCache(store: store)
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

        #expect(try batchBox.all().isEmpty)

        // Path A: verify via model
        #expect(!model.hasEvents(on: day10))

        // Path B: verify via direct ObjectBox
        let persisted = try batchBox.all()
        #expect(persisted.isEmpty)
        let persistedEvents = try eventBox.all()
        #expect(persistedEvents.isEmpty)
    }

    @Test func addEventToBatchPersistsViaModelAndVerifiableInStorage() async throws {
        let store = makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let (cache, _) = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)

        model.selectedColor = .option1
        model.changeEvent(event(day: 10))
        model.changeEvent(event(day: 11))
        model.changeEvent(event(day: 12))
        model.daySelectionManager.selectionMode = .multiple

        model.prepareAddEditEventBatchViewModel()
        let addEdit = model.addEditBatchListViewModel.addEditEventBatchModel
        addEdit.eventBatchName = "Three Events"
        addEdit.selectedColor = .option1
        addEdit.recolorAllEvents()
        #expect(addEdit.save())
        model.resetSelectedDays()

        #expect(try await waitForBatchCount(1, in: store))

        // Path A: verify via model
        #expect(model.hasEvents(on: date(year: 2026, month: 6, day: 10)))
        #expect(model.hasEvents(on: date(year: 2026, month: 6, day: 11)))
        #expect(model.hasEvents(on: date(year: 2026, month: 6, day: 12)))

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
        let store = makeStore()
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

        let (cache, _) = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)

        model.prepareAddEditBatchListViewModel(with: [day10])
        let batchList = model.addEditBatchListViewModel
        batchList.prepareAddEditBatchViewModel(with: batchList.eventBatches[0])

        let addEdit = batchList.addEditEventBatchModel
        addEdit.toggleEvent(on: day12) // Remove day12 event
        #expect(addEdit.save())
        model.resetSelectedDays()

        // Path A: verify via model
        #expect(model.hasEvents(on: day10))
        #expect(!model.hasEvents(on: day12))

        // Path B: verify via direct ObjectBox
        let persistedEvents = try eventBox.all()
        #expect(persistedEvents.count == 1)
        #expect(Calendar.current.isDate(persistedEvents[0].date, inSameDayAs: day10))
    }

    @Test func batchUpdateWithNewColorPersistsViaModelAndVerifiableInStorage() async throws {
        let store = makeStore()
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

        let (cache, _) = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)

        model.prepareAddEditBatchListViewModel(with: [day10])
        let batchList = model.addEditBatchListViewModel
        batchList.prepareAddEditBatchViewModel(with: batchList.eventBatches[0])

        let addEdit = batchList.addEditEventBatchModel
        addEdit.selectedColor = .option3
        addEdit.recolorAllEvents()
        #expect(addEdit.save())
        model.resetSelectedDays()

        #expect(try await waitForBatchCount(1, in: store))

        // Path A: verify via model
        #expect(model.hasEvents(on: day10))

        // Path B: verify via direct ObjectBox
        let persisted = try batchBox.all()[0]
        #expect(persisted.color == "eventColorOption3")
        let persistedEvents = Array(persisted.events)
        #expect(persistedEvents.count == 1)
        #expect(persistedEvents[0].color == "eventColorOption3")
    }

    @Test func twoIndependentBatchesBothPersistViaModelAndVerifiableInStorage() async throws {
        let store = makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let (cache, _) = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)

        // Create batch A
        model.selectedColor = .option1
        model.changeEvent(event(day: 10))
        model.daySelectionManager.selectionMode = .multiple
        model.prepareAddEditEventBatchViewModel()
        let addEditA = model.addEditBatchListViewModel.addEditEventBatchModel
        addEditA.eventBatchName = "Batch A"
        addEditA.selectedColor = .option1
        addEditA.recolorAllEvents()
        #expect(addEditA.save())
        model.resetSelectedDays()

        #expect(try await waitForBatchCount(1, in: store))

        // Create batch B
        model.selectedColor = .option3
        model.changeEvent(event(day: 20))
        model.daySelectionManager.selectionMode = .multiple
        model.prepareAddEditEventBatchViewModel()
        let addEditB = model.addEditBatchListViewModel.addEditEventBatchModel
        addEditB.eventBatchName = "Batch B"
        addEditB.selectedColor = .option3
        addEditB.recolorAllEvents()
        #expect(addEditB.save())
        model.resetSelectedDays()

        #expect(try await waitForBatchCount(2, in: store))

        // Path A: verify via model
        #expect(model.hasEvents(on: date(year: 2026, month: 6, day: 10)))
        #expect(model.hasEvents(on: date(year: 2026, month: 6, day: 20)))

        // Path B: verify via direct ObjectBox
        let batchBox = store.box(for: PPEventBatch.self)
        let batches = try batchBox.all()
        #expect(batches.count == 2)
        let names = Set(batches.map(\.title))
        #expect(names.contains("Batch A"))
        #expect(names.contains("Batch B"))
    }

    @Test func calendarUpdateAfterBatchCommitRetrievesCorrectBatchesViaCache() async throws {
        let store = makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let (cache, _) = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)

        model.selectedColor = .option1
        model.changeEvent(event(day: 10))
        model.daySelectionManager.selectionMode = .multiple
        model.prepareAddEditEventBatchViewModel()
        let addEdit = model.addEditBatchListViewModel.addEditEventBatchModel
        addEdit.eventBatchName = "Persisted"
        addEdit.selectedColor = .option1
        addEdit.recolorAllEvents()
        #expect(addEdit.save())
        model.resetSelectedDays()

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
        let store = makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let (cache, _) = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)

        model.selectedColor = .option3
        model.changeEvent(event(day: 10, color: "eventColorOption3"))
        model.daySelectionManager.selectionMode = .multiple

        model.prepareAddEditEventBatchViewModel()
        let addEdit = model.addEditBatchListViewModel.addEditEventBatchModel
        addEdit.eventBatchName = "Custom Color"
        addEdit.selectedColor = .option3
        addEdit.recolorAllEvents()
        #expect(addEdit.save())
        model.resetSelectedDays()

        #expect(try await waitForBatchCount(1, in: store))

        // Path A: verify via model
        #expect(model.hasEvents(on: date(year: 2026, month: 6, day: 10)))

        // Path B: verify via direct ObjectBox
        let eventBox = store.box(for: PPEvent.self)
        let events = try eventBox.all()
        #expect(events.count == 1)
        #expect(events[0].color == "eventColorOption3")
    }

    @Test func editEventColorInBatchPersistsViaModelAndVerifiableInStorage() async throws {
        let store = makeStore()
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

        let (cache, _) = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)

        model.prepareAddEditBatchListViewModel(with: [day10])
        let batchList = model.addEditBatchListViewModel
        batchList.prepareAddEditBatchViewModel(with: batchList.eventBatches[0])

        let addEdit = batchList.addEditEventBatchModel
        let first = addEdit.addEditListViewModel.events[0]
        addEdit.addEditListViewModel.prepareAddEditViewModel(with: first)
        addEdit.addEditListViewModel.addEditEventModel.selectedColor = .option2
        #expect(addEdit.addEditListViewModel.addEditEventModel.save())
        addEdit.addEditListViewModel.apply(with: addEdit.addEditListViewModel.addEditEventModel.event!)
        #expect(addEdit.save())
        model.resetSelectedDays()

        #expect(try await waitForBatchCount(1, in: store))

        // Path A: verify via model
        #expect(model.hasEvents(on: day10))

        // Path B: verify via direct ObjectBox
        let eventBox = store.box(for: PPEvent.self)
        let events = try eventBox.all()
        #expect(events.count == 1)
        #expect(events[0].color == "eventColorOption2")
    }

    @Test func removeAllEventsFromBatchDeletesBatchAndEvents() async throws {
        let store = makeStore()
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

        let (cache, _) = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)

        model.prepareAddEditBatchListViewModel(with: [day10])
        let batchList = model.addEditBatchListViewModel
        batchList.prepareAddEditBatchViewModel(with: batchList.eventBatches[0])

        let addEdit = batchList.addEditEventBatchModel
        addEdit.toggleEvent(on: day10) // Remove all events
        #expect(addEdit.save())
        model.resetSelectedDays()

        // Path A: verify via model
        #expect(!model.hasEvents(on: day10))

        // Path B: verify via direct ObjectBox
        let persistedBatches = try batchBox.all()
        #expect(persistedBatches.isEmpty)
        let persistedEvents = try eventBox.all()
        #expect(persistedEvents.isEmpty)
    }

    @Test func createMultipleBatchesOnDifferentDaysPersistsCorrectly() async throws {
        let store = makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let (cache, _) = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)

        let day5 = date(year: 2026, month: 6, day: 5)
        let day15 = date(year: 2026, month: 6, day: 15)

        // Batch on day 5
        model.selectedColor = .option1
        model.changeEvent(EventDataSource(name: "Day5 Event", date: day5, color: PCColorOption.option1.colorName))
        model.daySelectionManager.selectionMode = .multiple
        model.prepareAddEditEventBatchViewModel()
        let addEditA = model.addEditBatchListViewModel.addEditEventBatchModel
        addEditA.eventBatchName = "Day 5 Batch"
        addEditA.selectedColor = .option1
        addEditA.recolorAllEvents()
        #expect(addEditA.save())
        model.resetSelectedDays()

        #expect(try await waitForBatchCount(1, in: store))

        // Batch on day 15
        model.selectedColor = .option4
        model.changeEvent(EventDataSource(name: "Day15 Event", date: day15, color: PCColorOption.option4.colorName))
        model.daySelectionManager.selectionMode = .multiple
        model.prepareAddEditEventBatchViewModel()
        let addEditB = model.addEditBatchListViewModel.addEditEventBatchModel
        addEditB.eventBatchName = "Day 15 Batch"
        addEditB.selectedColor = .option4
        addEditB.recolorAllEvents()
        #expect(addEditB.save())
        model.resetSelectedDays()

        #expect(try await waitForBatchCount(2, in: store))

        // Path A: verify via model
        #expect(model.hasEvents(on: day5))
        #expect(model.hasEvents(on: day15))

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

    // MARK: - Calendar CRUD signal verification

    @Test func createCalendarSendsAddSignal() async throws {
        let store = makeStore()
        defer { store.close() }

        let (cache, _) = makeCache(store: store)

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
        let store = makeStore()
        defer { store.close() }

        let (cache, _) = makeCache(store: store)
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
        let store = makeStore()
        defer { store.close() }

        let (cache, _) = makeCache(store: store)
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

    // MARK: - Batch persistence via save(for:) round-trip

    @Test func saveForCalendarRoundTripsBatchDataThroughCache() async throws {
        let store = makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let (cache, _) = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)

        // Create and commit batch
        model.selectedColor = .option1
        model.changeEvent(event(day: 10))
        model.daySelectionManager.selectionMode = .multiple
        model.prepareAddEditEventBatchViewModel()
        let addEdit = model.addEditBatchListViewModel.addEditEventBatchModel
        addEdit.eventBatchName = "Round Trip"
        addEdit.selectedColor = .option1
        addEdit.recolorAllEvents()
        #expect(addEdit.save())
        model.resetSelectedDays()

        #expect(try await waitForBatchCount(1, in: store))

        // Re-fetch from cache to verify round-trip
        let freshCache = CalendarCache(manager: CalendarManager(service: ObjectBoxCalendarStorage(store: store)))
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
        let store = makeStore()
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

        let (cache, _) = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)

        // Edit batch: remove day15 event, rename
        model.prepareAddEditBatchListViewModel(with: [day10])
        let batchList = model.addEditBatchListViewModel
        batchList.prepareAddEditBatchViewModel(with: batchList.eventBatches[0])

        let addEdit = batchList.addEditEventBatchModel
        addEdit.eventBatchName = "Edited"
        addEdit.toggleEvent(on: day15) // Remove day15
        #expect(addEdit.save())
        model.resetSelectedDays()

        #expect(try await waitForBatchCount(1, in: store))

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
}
