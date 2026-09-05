//
//  TwoSingleDayBatchesReproTests.swift
//  SingleCalendarFeatureTests
//
//  Reproduces the reported bug: creating two single-day batches via the
//  BatchEditor within the same app session. The SECOND day's event fails to
//  show on the year view (but persists to storage).
//

import Testing
import Foundation
import ObjectBox
import DSKit
@testable import CorePersistence
@testable import SingleCalendarFeature

@MainActor
struct TwoSingleDayBatchesReproTests {

    private func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)!
    }

    private func makeStore() throws -> Store {
        try Store(directoryPath: "memory:repro-\(UUID().uuidString)")
    }

    private func makeCache(store: Store) -> CalendarCache {
        CalendarCache(repository: ObjectBoxCalendarStorage(store: store))
    }

    private func makeCalendar(in store: Store) -> PPCalendar {
        let calendar = PPCalendar(name: "Test", year: 2026, numberOfColumns: 3)
        try! store.box(for: PPCalendar.self).put(calendar)
        return calendar
    }

    private func dayEvents(_ model: SingleCalendarModel, _ date: Date) -> [String] {
        var result: [String] = []
        for month in model.yearModel.months {
            for week in month.weeks {
                for day in week.days {
                    guard let d = day.date,
                          Calendar.current.isDate(d, inSameDayAs: date) else { continue }
                    if day.isInCurrentMonth {
                        result = day.events
                    }
                }
            }
        }
        return result
    }

    private func dayModel(in model: SingleCalendarModel, for date: Date) -> PCCalendarDayModel? {
        for month in model.yearModel.months {
            for week in month.weeks {
                for day in week.days {
                    guard let d = day.date,
                          day.isInCurrentMonth,
                          Calendar.current.isDate(d, inSameDayAs: date) else { continue }
                    return day
                }
            }
        }
        return nil
    }

    // MARK: - Bug reproduction

    @Test func secondSingleDayBatchDoesNotRenderOnYearView() async throws {
        let store = try makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let cache = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)
        #expect(model.state == .content)

        let day9 = date(year: 2026, month: 11, day: 9)
        let day10 = date(year: 2026, month: 11, day: 10)

        // ── First batch on day 9 ──
        model.prepareAddEditEventBatchViewModel(for: day9)
        var addEdit = model.makeBatchEditor()
        addEdit.eventBatchName = "First"
        addEdit.selectedColor = .option1
        #expect(addEdit.save())
        model.commitPendingBatch(addEdit.eventBatch)

        // Wait for the first batch to persist + reload via cache change.
        #expect(try await waitForBatchCount(1, in: store))
        await settle()

        #expect(model.hasEvents(on: day9))
        #expect(!dayEvents(model, day9).isEmpty)

        // ── Second batch on day 10 ──
        model.prepareAddEditEventBatchViewModel(for: day10)
        addEdit = model.makeBatchEditor()
        addEdit.eventBatchName = "Second"
        addEdit.selectedColor = .option1
        #expect(addEdit.save())
        model.commitPendingBatch(addEdit.eventBatch)

        // Persistence check (should pass - events are persisted).
        #expect(try await waitForBatchCount(2, in: store))
        await settle()

        // After the fix: both day markers must appear on the year view.
        #expect(model.hasEvents(on: day10),
                "Bug: day 10 has no events in originalBatches after commitPendingBatch")
        #expect(!dayEvents(model, day10).isEmpty,
                "Bug: day 10 marker missing on year view")

        // Both store entries present.
        let batchBox = store.box(for: PPEventBatch.self)
        #expect(try batchBox.all().count == 2)
    }

    // MARK: - Regression: fetch must not rebuild the year model

    @Test func fetchKeepsDayModelInstancesStable() async throws {
        let store = try makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let cache = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)
        #expect(model.state == .content)

        let day9 = date(year: 2026, month: 11, day: 9)
        let originalDay = dayModel(in: model, for: day9)
        #expect(originalDay != nil)

        // Commit a batch, which triggers an async save -> cache change -> fetch.
        model.prepareAddEditEventBatchViewModel(for: day9)
        let addEdit = model.makeBatchEditor()
        addEdit.eventBatchName = "First"
        addEdit.selectedColor = .option1
        #expect(addEdit.save())
        model.commitPendingBatch(addEdit.eventBatch)

        #expect(try await waitForBatchCount(1, in: store))
        await settle()

        // The day model instance must be the SAME object: fetch must mutate
        // events in place rather than rebuilding the whole year model.
        let afterFetch = dayModel(in: model, for: day9)
        #expect(afterFetch != nil)
        #expect(afterFetch === originalDay,
                "fetch rebuilt the year model; day instance changed")
        #expect(!(afterFetch?.events.isEmpty ?? true),
                "day 9 must show its committed event after fetch")
    }

    // MARK: - Accessibility identifiers

    @Test func calendarDaysHaveUniqueAccessibilityIdentifiers() async throws {
        let store = try makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let cache = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)
        #expect(model.state == .content)

        var seenIDs = Set<String>()
        for month in model.yearModel.months {
            for week in month.weeks {
                for day in week.days {
                    guard let _ = day.date else { continue }
                    let id = day.accessibilityID
                    #expect(!id.isEmpty, "Day accessibilityID must not be empty")
                    #expect(!seenIDs.contains(id),
                            "Duplicate accessibilityID: \(id)")
                    seenIDs.insert(id)
                }
            }
        }
    }

    @Test func dayAccessibilityIdentifiersContainDate() async throws {
        let store = try makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let cache = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)
        #expect(model.state == .content)

        let day9 = date(year: 2026, month: 11, day: 9)
        let expectedID = "day-11-2026-11-09"

        var foundInMonthDay = false
        for month in model.yearModel.months {
            for week in month.weeks {
                for day in week.days {
                    guard let d = day.date,
                          Calendar.current.isDate(d, inSameDayAs: day9),
                          day.isInCurrentMonth else { continue }
                    #expect(day.accessibilityID == expectedID,
                            "Day 9 accessibilityID should be \(expectedID), got \(day.accessibilityID)")
                    foundInMonthDay = true
                }
            }
        }
        #expect(foundInMonthDay, "Day 9 should appear as an in-month day exactly once")
    }

    @Test func saveButtonHasAccessibilityIdentifier() {
        #expect(AddEditEventBatchView.saveButtonAccessibilityIdentifier == "batch-save-button")
    }

    // MARK: - Duplicate batch regression

    @Test func editingExistingBatchAddingDaysDoesNotCreateDuplicates() async throws {
        let store = try makeStore()
        defer { store.close() }

        let ppCalendar = makeCalendar(in: store)
        let cache = makeCache(store: store)
        let model = SingleCalendarModel(calendarid: Int64(ppCalendar.id), cache: cache)
        await model.fetch(force: true)
        #expect(model.state == .content)

        let day10 = date(year: 2026, month: 11, day: 10)
        let day12 = date(year: 2026, month: 11, day: 12)

        // ── Create initial batch on day 10 ──
        model.prepareAddEditEventBatchViewModel(for: day10)
        var addEdit = model.makeBatchEditor()
        addEdit.eventBatchName = "Original"
        addEdit.selectedColor = .option1
        #expect(addEdit.save())
        model.commitPendingBatch(addEdit.eventBatch)

        #expect(try await waitForBatchCount(1, in: store))
        await settle()

        // Verify initial state - single batch
        #expect(model.originalBatches.count == 1)
        #expect(model.hasEvents(on: day10))

        // Reload from the store so the committed batch carries its persisted id,
        // matching the state after a fresh app session / calendar re-open.
        let reopenedModel = SingleCalendarModel(
            calendarid: Int64(ppCalendar.id),
            cache: makeCache(store: store)
        )
        await reopenedModel.fetch(force: true)
        #expect(reopenedModel.state == .content)
        #expect(reopenedModel.originalBatches.count == 1)

        // ── Simulate: open batch list for day 10, select the batch, edit it ──
        #expect(reopenedModel.batches(for: day10).count == 1)
        let existingBatch = reopenedModel.batches(for: day10)[0]
        #expect(existingBatch.id != 0, "Persisted batch should have a real id")

        // Open editor for existing batch
        addEdit = reopenedModel.makeBatchEditor()
        addEdit.load(existingBatch)
        #expect(addEdit.eventBatchId != 0)
        #expect(addEdit.eventsSelectionManager.events.count == 1)

        // Add another day (day 12) via toggle
        addEdit.toggleEvent(on: day12)
        #expect(addEdit.eventsSelectionManager.events.count == 2)

        // Save the edited batch
        #expect(addEdit.save())
        reopenedModel.commitPendingBatch(addEdit.eventBatch)

        #expect(try await waitForBatchCount(1, in: store))
        await settle()

        // ── Critical assertion: NO DUPLICATES in originalBatches ──
        // The bug was: originalBatches would contain 2 batches with same key
        // (one old, one new) causing display duplicates
        let finalBatches = reopenedModel.originalBatches

        // Should still be exactly 1 batch (the original was updated, not duplicated)
        #expect(finalBatches.count == 1, "Expected 1 batch after edit, got \(finalBatches.count)")

        // Verify the batch has both events
        let updatedBatch = finalBatches[0]
        #expect(updatedBatch.events.count == 2)
        let eventDates = updatedBatch.events.map(\.date).sorted()
        #expect(eventDates[0] == day10)
        #expect(eventDates[1] == day12)

        // Verify no duplicate keys in originalBatches
        let keys = finalBatches.map { reopenedModel.key(for: $0) }
        let uniqueKeys = Set(keys)
        #expect(keys.count == uniqueKeys.count,
                "Duplicate batch keys detected in originalBatches: \(keys)")

        // Verify day markers appear correctly on year view
        #expect(reopenedModel.hasEvents(on: day10))
        #expect(reopenedModel.hasEvents(on: day12))
        #expect(!dayEvents(reopenedModel, day10).isEmpty)
        #expect(!dayEvents(reopenedModel, day12).isEmpty)

        // Store should have exactly 1 batch
        let batchBox = store.box(for: PPEventBatch.self)
        #expect(try batchBox.all().count == 1)
        let persistedBatch = try batchBox.all()[0]
        #expect(persistedBatch.title == "Original")
        #expect(try store.box(for: PPEvent.self).all().count == 2)
    }

    // MARK: - Helpers

    private func waitForBatchCount(_ expected: Int, in store: Store, timeout: TimeInterval = 10) async throws -> Bool {
        let batchBox = store.box(for: PPEventBatch.self)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try batchBox.all().count >= expected { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return try batchBox.all().count >= expected
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(500))
    }
}
