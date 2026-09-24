//
//  EventEditorThenBatchSaveDuplicateTests.swift
//  SingleCalendarFeatureTests
//
//  Reproduces the reported bug: creating a new single-day batch via the day tap,
//  editing its only event, saving the EVENT, then saving the BATCH.  The second
//  save must UPDATE the already-persisted batch, not append a duplicate with the
//  same event.
//

import Testing
import Foundation
import ObjectBox
import DSKit
import CoreDomain
@testable import CorePersistence
@testable import SingleCalendarFeature

@MainActor
struct EventEditorThenBatchSaveDuplicateTests {

    private func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)!
    }

    private func makeStore() throws -> Store {
        try Store(directoryPath: "memory:duplicate-\(UUID().uuidString)")
    }

    /// Builds the model exactly like `PCCalendarSession` does in the app, i.e.
    /// the shared events-selection manager carries the persistence cache. This
    /// matters: in the app the batch editor persists through the manager.
    private func makeModel(store: Store) -> (PPCalendar, CalendarCache, SingleCalendarModel) {
        let calendar = PPCalendar(name: "Test", year: 2026, numberOfColumns: 3)
        try! store.box(for: PPCalendar.self).put(calendar)

        let cache = CalendarCache(repository: ObjectBoxCalendarStorage(store: store))
        let dataProvider = PCCalendarDataProvider()
        let daySelectionManager = PCCalendarDaySelectionManager()
        let eventsSelectionManager = PCEventsSelectionManager(
            cache: cache,
            dataProvider: dataProvider,
            daySelectionManager: daySelectionManager,
            columnCountResolver: { $0 }
        )
        let model = SingleCalendarModel(
            calendarid: Int64(calendar.id),
            cache: cache,
            dataProvider: dataProvider,
            eventsSelectionManager: eventsSelectionManager,
            daySelectionManager: daySelectionManager,
            columnCountResolver: { $0 }
        )
        return (calendar, cache, model)
    }

    private func waitForRealBatches(in manager: PCEventsSelectionManager, timeout: TimeInterval = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if manager.batches.contains(where: { $0.id != 0 }) { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return manager.batches.contains(where: { $0.id != 0 })
    }

    // MARK: - Bug reproduction

    /// STR:
    /// 1) Open calendar
    /// 2) Tap a day without events  -> new-batch editor with a placeholder event
    /// 3) Enter a batch name
    /// 4) Tap the event in the list  -> event editor
    /// 5) Enter an event name
    /// 6) Save (event)   -> auto-persists the batch, store assigns a real id
    /// 7) Save (batch)
    /// 8) Re-open the day
    /// EB: exactly one batch.  AB: two batches with the same event.
    @Test func savingEventThenBatchDoesNotDuplicateNewBatch() async throws {
        let store = try makeStore()
        defer { store.close() }

        let (ppCalendar, _, model) = makeModel(store: store)
        await model.fetch(force: true)
        #expect(model.state == .content)

        let day20 = date(year: 2026, month: 11, day: 20)
        #expect(!model.hasEvents(on: day20), "Precondition: the tapped day has no events")

        // 2) Tap the day: stages the placeholder event in the shared manager.
        model.prepareAddEditEventBatchViewModel(for: day20)

        // Mirror AddEditEventBatchScreen: batch editor bound to the shared manager.
        let batchEditor = AddEditEventBatchViewModel(
            eventsSelectionManager: model.eventsSelectionManager,
            calendarId: Int64(ppCalendar.id),
            selectedDay: day20
        )
        // `.task { viewModel.setup() }` runs before the user types anything.
        batchEditor.setup()
        #expect(batchEditor.eventBatchId == 0, "A brand-new batch starts without a persisted id")

        // 3) Enter the batch name (color is seeded from the placeholder event).
        batchEditor.eventBatchName = "Edited Batch"

        // 4) Tap the event row in the list -> event editor with the staged event.
        let stagedEvent = try #require(model.eventsSelectionManager.events.first)
        let eventEditor = AddEditEventViewModel(
            eventsSelectionManager: model.eventsSelectionManager,
            event: stagedEvent
        )
        // 5) Enter the event name.
        eventEditor.eventName = "Edited Event"

        // 6) Save the event. This applies the event and auto-persists the batch
        //    (onEventApplied -> persistBatch), so the store assigns a real id.
        #expect(eventEditor.save())
        let manager = model.eventsSelectionManager
        let batchBox = store.box(for: PPEventBatch.self)
        let eventBox = store.box(for: PPEvent.self)
        #expect(await waitForRealBatches(in: manager),
                "The batch must be reloaded with a real persisted id after the event save")
        #expect(manager.batches.count == 1)
        let persistedID = manager.batches[0].id
        #expect(persistedID != 0)

        // 7) Save the batch editor.
        #expect(batchEditor.save())
        // Persistence runs in a background task; let the store catch up.
        let persistDeadline = Date().addingTimeInterval(5)
        while Date() < persistDeadline {
            if (try? batchBox.all())?.count ?? -1 == manager.batches.count { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        // 8) Re-open the day: exactly ONE batch with the single edited event.
        #expect(manager.batches.count == 1,
                "Bug: a second, duplicate batch was created by the batch Save: \(manager.batches)")
        #expect(model.batches(for: day20).count == 1,
                "Bug: the day now lists two batches: \(model.batches(for: day20))")
        #expect(model.hasEvents(on: day20))

        let storedBatches = try batchBox.all()
        #expect(storedBatches.count == 1,
                "Bug: the store now holds two batches: \(storedBatches)")

        let storedEvents = try eventBox.all()
        #expect(storedEvents.count == 1,
                "Bug: the store now holds the same event twice: \(storedEvents)")
    }
}