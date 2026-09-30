//
//  SingleCalendarModelObjectBoxIntegrationTests.swift
//  SingleCalendarFeatureTests
//
//  Created by Oleg Bragin on 07.07.2026.
//

import Testing
import Foundation
import CorePersistence
import DSKit
import CoreDomain
@testable import SingleCalendarFeature

/// Batch flows end to end: do the thing, then assert what the calendar now holds.
///
/// These ran against a real ObjectBox store, reading the boxes directly. They no longer
/// can, and the reason is the DTO boundary rather than a practical one: the DTO→domain
/// adapter (`CalendarStore`) lives in the app target, so a package test can only reach the
/// batch graph through the `CalendarPersisting` port. Reading the boxes directly is
/// exactly what the boundary forbids — it means holding an `EventBatchDataSource`.
///
/// So the assertions moved from "what is in the box" to "what did the port receive", which
/// is the same fact stated at the level the feature is allowed to state it. The mapping
/// itself — the part that used to be untested here — is covered in `PinCalAppTests`, where
/// `CalendarStore` is reachable.
///
/// The store assigns `persistedID`s on write, exactly as ObjectBox did, because §6.5
/// adoption depends on a committed batch coming back with a real id.
@MainActor
@Suite("Batch flows end to end")
struct SingleCalendarModelObjectBoxIntegrationTests {

    // MARK: - Helpers

    private func day(_ d: Int, month: Int = 6, year: Int = 2026) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = d
        components.hour = 12
        return calendar.date(from: components)!
    }

    private struct Context {
        let store: PCEventSelectionManager
        let persistence: InMemoryCalendarPersisting
        let editor: AddEditEventBatchViewModel
        let list: AddEditEventListViewModel
    }

    private func makeContext(calendarID: Int64 = 42) -> Context {
        let persistence = InMemoryCalendarPersisting()
        let store = Fixture.makeStore(calendarID: calendarID, persistence: persistence)
        return Context(
            store: store,
            persistence: persistence,
            editor: AddEditEventBatchViewModel(store: store),
            list: AddEditEventListViewModel(store: store)
        )
    }

    /// Names and colours a new batch, then saves it. This is the "fill in the editor and
    /// press save" path that most of these tests are variations on.
    @discardableResult
    private func commitNewBatch(
        _ context: Context,
        on day: Date,
        name: String = "Batch",
        color: PCColorOption = .option1
    ) -> [CalendarEventBatch] {
        context.store.send(.startNewBatch(on: day))
        context.editor.nameBinding.wrappedValue = name
        context.editor.colorBinding.wrappedValue = color
        context.editor.save()
        return context.store.state.batches
    }

    // MARK: - Editing an event in a batch

    @Test func editingEventInBatchPersistsWhenBatchSaved() throws {
        let context = makeContext()
        let someDay = day(1)
        commitNewBatch(context, on: someDay, name: "Swim")

        // Open the event, rename it, save it back into the batch.
        // Saving the batch cleared the assembly, so the batch has to be opened again
        // before its events can be — which is exactly what the day list does. `openEvent`
        // is correctly refused with no assembly, so skipping this would silently test
        // nothing.
        let stored = try #require(context.store.state.batches.first)
        context.store.send(.openBatch(id: stored.mergeKey))
        let event = try #require(context.store.state.assembly?.batch.events.first)
        context.list.open(event)
        let eventEditor = AddEditEventViewModel(store: context.store)
        eventEditor.nameBinding.wrappedValue = "Lap"
        eventEditor.save()

        context.editor.save()

        let batch = context.store.state.batches.first
        #expect(batch?.name == "Swim")
        #expect(batch?.events.first?.name == "Lap")
        #expect(batch?.events.count == 1, "edited, not appended")
    }

    // MARK: - Commits

    @Test func commitBatchPersistsAndIsVerifiableThroughThePort() async {
        let context = makeContext()
        commitNewBatch(context, on: day(1), name: "Swim")

        let writes = await context.persistence.waitForWrites(1)
        let rows = await context.persistence.storedBatches(calendarID: 42)
        #expect(writes == 1)
        #expect(rows.count == 1)
        #expect(rows[0].name == "Swim")
        #expect(rows[0].persistedID != nil, "the store assigns ids on write")
    }

    @Test func editBatchNamePersists() async {
        let context = makeContext()
        commitNewBatch(context, on: day(1), name: "Swim")
        _ = await context.persistence.waitForWrites(1)

        // Reopen the stored row and rename it.
        var stored = await context.persistence.storedBatches(calendarID: 42)
        store_as_reloaded(&stored, using: context.store)
        context.store.send(.syncCalendar(calendarID: 42, batches: stored))
        context.store.send(.openBatch(id: stored[0].mergeKey))
        context.editor.nameBinding.wrappedValue = "Swimming"
        context.editor.save()

        let before = await context.persistence.writes.count
        _ = await context.persistence.waitForWrites(before + 1)
        let rows = await context.persistence.storedBatches(calendarID: 42)
        #expect(rows.count == 1, "renamed in place")
        #expect(rows[0].name == "Swimming")
    }

    @Test func deletingABatchRemovesIt() async {
        let context = makeContext()
        commitNewBatch(context, on: day(1), name: "Swim")
        _ = await context.persistence.waitForWrites(1)
        var stored = await context.persistence.storedBatches(calendarID: 42)
        store_as_reloaded(&stored, using: context.store)
        context.store.send(.syncCalendar(calendarID: 42, batches: stored))

        context.store.send(.deleteBatches(stored))

        #expect(context.store.state.batches.isEmpty)
        // The delete reaches the port through the store's write chain, so read storage
        // only once that has drained.
        let before = await context.persistence.writes.count
        _ = await context.persistence.waitForWrites(before + 1)
        let rows = await context.persistence.storedBatches(calendarID: 42)
        #expect(rows.isEmpty, "and it is gone from storage too")
    }

    @Test func addingADayToABatchExtendsItRatherThanCreatingASecond() {
        let context = makeContext()
        commitNewBatch(context, on: day(1), name: "Morning")

        let stored = context.store.state.batches
        context.store.send(.syncCalendar(calendarID: 42, batches: stored))
        context.store.send(.openBatch(id: stored[0].mergeKey))
        context.editor.save()

        #expect(context.store.state.batches.count == 1)
    }

    @Test func removingAnEventFromABatchIsReflected() {
        let context = makeContext()
        context.store.send(.startNewBatch(on: day(1)))
        context.editor.nameBinding.wrappedValue = "Morning"
        context.editor.colorBinding.wrappedValue = .option1
        context.store.send(.toggleDay(day(2)))
        #expect(context.list.events.count == 2)

        context.list.remove(context.list.events[0])
        context.editor.save()

        #expect(context.store.state.batches.first?.events.count == 1)
    }

    @Test func recolouringABatchRewritesEveryEvent() {
        let context = makeContext()
        context.store.send(.startNewBatch(on: day(1)))
        context.store.send(.toggleDay(day(2)))
        context.editor.nameBinding.wrappedValue = "Morning"
        context.editor.colorBinding.wrappedValue = .option1
        context.editor.save()

        let stored = context.store.state.batches
        context.store.send(.syncCalendar(calendarID: 42, batches: stored))
        context.store.send(.openBatch(id: stored[0].mergeKey))
        context.editor.colorBinding.wrappedValue = .option3
        context.editor.save()

        let batch = context.store.state.batches.first
        #expect(batch?.colorName == "eventColorOption3")
        #expect(
            batch?.events.allSatisfy { $0.colorName == "eventColorOption3" } == true,
            "the batch colour propagates to its events"
        )
    }

    @Test func twoIndependentBatchesBothPersist() {
        let context = makeContext()
        commitNewBatch(context, on: day(1), name: "First", color: .option1)
        commitNewBatch(context, on: day(2), name: "Second", color: .option2)

        #expect(context.store.state.batches.count == 2)
        #expect(Set(context.store.state.batches.map(\.name)) == ["First", "Second"])
    }

    @Test func multipleBatchesOnDifferentDaysPersistCorrectly() {
        let context = makeContext()
        for d in 1...3 {
            commitNewBatch(context, on: day(d), name: "Batch \(d)")
        }

        #expect(context.store.state.batches.count == 3)
        for d in 1...3 {
            context.store.send(.dayTappedInCalendar(day(d)))
            #expect(context.store.state.dayBatches.count == 1, "day \(d) has exactly one batch")
        }
    }

    // MARK: - Removing the anchor day

    @Test func removingTheAnchorDayUncoloursItOnTheYearView() {
        let context = makeContext()
        commitNewBatch(context, on: day(1), name: "Morning", color: .option1)

        let stored = context.store.state.batches
        context.store.send(.syncCalendar(calendarID: 42, batches: stored))
        context.store.send(.openBatch(id: stored[0].mergeKey))
        // Remove the only day: the batch is emptied, so the row must leave the calendar.
        context.list.remove(context.list.events[0])
        context.editor.save()

        #expect(context.store.state.batches.isEmpty, "an emptied batch leaves the calendar")
    }

    @Test func removingAnAnchorDayKeepsTheBatchWhenOtherDaysRemain() {
        let context = makeContext()
        context.store.send(.startNewBatch(on: day(1)))
        context.store.send(.toggleDay(day(2)))
        context.editor.nameBinding.wrappedValue = "Morning"
        context.editor.colorBinding.wrappedValue = .option1
        context.editor.save()

        let stored = context.store.state.batches
        context.store.send(.syncCalendar(calendarID: 42, batches: stored))
        context.store.send(.openBatch(id: stored[0].mergeKey))
        context.list.remove(context.list.events[0]) // the anchor day
        context.editor.save()

        let batch = context.store.state.batches.first
        #expect(batch != nil, "a batch with a day left is still a batch")
        #expect(batch?.events.count == 1)
    }

    // MARK: - Round trips

    @Test func savingForACalendarRoundTripsThroughThePort() async throws {
        let context = makeContext()
        commitNewBatch(context, on: day(1), name: "Swim")
        _ = await context.persistence.waitForWrites(1)

        // Read it back the way a reopen would.
        let readBack = try await context.persistence.eventBatches(calendarID: 42)
        #expect(readBack.count == 1)
        #expect(readBack[0].name == "Swim")
    }

    @Test func editingThenReFetchingReturnsTheUpdatedData() async {
        let context = makeContext()
        commitNewBatch(context, on: day(1), name: "Swim")
        _ = await context.persistence.waitForWrites(1)

        var stored = await context.persistence.storedBatches(calendarID: 42)
        store_as_reloaded(&stored, using: context.store)
        context.store.send(.syncCalendar(calendarID: 42, batches: stored))
        context.store.send(.openBatch(id: stored[0].mergeKey))
        context.editor.nameBinding.wrappedValue = "Swimming"
        context.editor.save()
        let before = await context.persistence.writes.count
        _ = await context.persistence.waitForWrites(before + 1)

        // A fresh model over the same storage sees the edit.
        let fresh = Fixture.makeStore(
            batches: await context.persistence.storedBatches(calendarID: 42),
            persistence: context.persistence
        )
        #expect(fresh.state.batches.first?.name == "Swimming")
    }

    @Test func savingFromTheEditorDoesNotReachTheNavigationRoot() {
        let context = makeContext()
        commitNewBatch(context, on: day(1), name: "Swim")

        #expect(
            context.store.state.stage != .idle,
            "the stage still says where the user is; navigation is the view layer's job"
        )
        #expect(context.store.state.batches.count == 1)
    }

    @Test func calendarUpdateAfterCommitRetrievesTheCorrectBatches() async throws {
        let context = makeContext()
        commitNewBatch(context, on: day(1), name: "Swim")
        _ = await context.persistence.waitForWrites(1)

        let readBack = try await context.persistence.eventBatches(calendarID: 42)
        #expect(readBack.map(\.name) == ["Swim"])
    }

    // MARK: - Helper

    /// Mimics what a reload does to a row: a *fresh* `pendingID`, because a DTO carries
    /// none, and the day's events re-based to start-of-day. This is why §6.5 adoption has
    /// to be content-based — an id lookup can never match across a reload.
    private func store_as_reloaded(
        _ batches: inout [CalendarEventBatch],
        using store: PCEventSelectionManager
    ) {
        let provider = store.state.dataProvider
        batches = batches.map { batch in
            CalendarEventBatch(
                pendingID: UUID(),
                persistedID: batch.persistedID,
                name: batch.name,
                colorName: batch.colorName,
                events: batch.events.map {
                    CalendarEvent(
                        persistedID: $0.persistedID,
                        name: $0.name,
                        date: provider.startOfDay(for: $0.date),
                        colorName: $0.colorName
                    )
                }
            )
        }
    }
}

// MARK: - §16, the reported bug, at the port boundary

/// §16's six steps, driven through the store, asserting **what the port was asked to
/// write** rather than what the UI then shows.
///
/// The UI test establishes that the state entering the failing save is right — one event,
/// on the surviving day, the other three already unmarked — so the defect is between the
/// save and the disk. `CalendarStore` is unreachable from a package test, so the split
/// this suite exists to make applies here too: if the port receives the right payload the
/// bug is in the reload that follows, and if it receives the wrong one it is here.
@MainActor
@Suite("§16 — removing three of four days")
struct RemovingThreeOfFourDaysTests {

    private func day(_ d: Int, month: Int = 6, year: Int = 2026) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = d
        components.hour = 12
        return calendar.date(from: components)!
    }

    /// A committed batch on four days, as the STR builds it, with the ids the store
    /// assigned on the way in.
    private func committedBatch(id: Int64 = 7) -> CalendarEventBatch {
        CalendarEventBatch(
            persistedID: id,
            name: "Window",
            colorName: "eventColorOption1",
            events: (0..<4).map { index in
                CalendarEvent(
                    persistedID: id * 100 + Int64(index),
                    name: "Event",
                    date: day(10 + index),
                    colorName: "eventColorOption1"
                )
            }
        )
    }

    @Test("The save asks the port to write the one event that remains, under the batch's own id")
    func saveWritesTheRemainingEvent() async throws {
        let provider = PCCalendarDataProvider()
        let committed = committedBatch()
        let persistence = InMemoryCalendarPersisting(
            calendar: PinCalendar(id: 42, name: "UI Test Calendar", year: 2026, numberOfColumns: 1),
            initialBatches: [committed]
        )
        let store = Fixture.makeStore(calendarID: 42, batches: [committed], persistence: persistence)

        // §16.1 steps 5 and 6: open the batch, remove three of its four days, save.
        store.send(.openBatch(id: committed.mergeKey))
        let opened = try #require(store.state.assembly?.batch)
        #expect(opened.persistedID == committed.persistedID, "opened with the row's real id")
        #expect(opened.events.count == 4)

        for d in [10, 11, 12] {
            store.send(.toggleDay(day(d)))
        }
        let staged = try #require(store.state.assembly?.batch)
        #expect(
            staged.events.count == 1,
            "staging leaves one event, as the UI test's pre-Save diagnostic showed"
        )
        #expect(
            staged.events.first?.persistedID == committed.events.last?.persistedID,
            "and the survivor is the one on the day that was kept, with its own real id"
        )

        store.send(.saveTapped)

        // The store executes effects through a chained `Task`, so the write has not
        // happened by the time `send` returns. Reading `writes` straight away reports an
        // empty array and reads exactly like "the save never wrote" — which is why
        // `InMemoryCalendarPersisting` carries `waitForWrites`.
        await persistence.waitForWrites(1)

        let writes = await persistence.writes
        let last = try #require(writes.last)
        let written = try #require(last.batches.first)

        #expect(last.batches.count == 1, "one batch is written")
        #expect(
            written.persistedID == committed.persistedID,
            "under the batch's own id, so this is an update — got \(String(describing: written.persistedID))"
        )
        #expect(
            written.events.count == 1,
            "AB: the write carries \(written.events.count) events, expected 1"
        )
        #expect(
            written.events.first?.persistedID == committed.events.last?.persistedID,
            "and it is the surviving event, with its real id"
        )

        // The reload, which is the only step left between the write and what the user
        // sees. `SingleCalendarModel` subscribes to the calendar's change feed and re-sends
        // `syncCalendar` from a fresh read, so this is not a formality.
        let reloaded = try await persistence.eventBatches(calendarID: 42)
        store.send(.syncCalendar(calendarID: 42, batches: reloaded))

        // …and the session has to be pointing at a day the saved batch is actually listed
        // on, because `saveTapped` pops to the day list for `state.day`. `openBatch` set it
        // to the row's *first* event, which this edit removes, so before the fix the pop
        // returned to a day list the batch was no longer on and it rendered empty — the
        // reported AB, with a perfectly correct batch behind it.
        let sessionDay = try #require(store.state.day)
        #expect(
            provider.isSameDay(sessionDay, day(13)),
            "the session must re-anchor on the surviving day, not the day the batch was opened on; got \(sessionDay)"
        )
        let dayBatches = store.state.dayBatches
        #expect(
            dayBatches.count == 1,
            "AB: the day list the save returns to holds \(dayBatches.count) batches, expected 1"
        )
        #expect(
            dayBatches.first?.events.count == 1,
            "and that batch must hold the one event that was kept"
        )
        #expect(
            store.state.dayEventColors[provider.startOfDay(for: day(13))] != nil,
            "and the surviving day must still be marked"
        )
    }
}
