//
//  SingleCalendarModelObjectBoxIntegrationTests.swift
//  SingleCalendarFeatureTests
//
//  Created by Oleg Bragin on 07.07.2026.
//

import Foundation
import Testing
import CoreDomain
import CorePersistence
import DSKit
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

    /// Names and colours a new batch, then leaves the editor. This is the "fill in the editor
    /// and go back" path that most of these tests are variations on.
    ///
    /// It used to end in `save()`. The checkmark is gone, so Back is the exit — and it is not
    /// just a different call: the batch is already in `state.batches` by the time Back runs,
    /// because every field wrote through as it was edited. Nothing here commits anything, which
    /// is the point the whole suite was quietly resting on a button for.
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
        context.store.send(.backTapped)
        return context.store.state.batches
    }

    // There was a test here named `editingEventInBatchPersistsWithoutAnySave`: it named a batch,
    // opened one of its events in the child editor, renamed it, and checked the batch already
    // held the name before the user left. The editor is gone, and with it any way to rename an
    // event — `toggling` appends a placeholder wearing the batch's colour and nothing here can
    // change that — so there is nothing for the test to assert.

    // MARK: - Commits

    @Test func commitBatchPersistsAndIsVerifiableThroughThePort() async {
        let context = makeContext()
        commitNewBatch(context, on: day(1), name: "Swim")

        // A name edit writes nothing until the editor is left with it, so the commit is the
        // write `backTapped` makes — not a debounced one that happened to beat it.
        //
        // **Premise changed.** This used to wait for two: the tap wrote the batch, and the
        // colour wrote it again. A tap writes nothing, and a colour already at its default
        // writes nothing either — so the whole commit is one write, and it is the one that
        // carries the name.
        let writes = await context.persistence.waitForWrites(1)
        let rows = await context.persistence.storedBatches(calendarID: 42)
        #expect(writes >= 1, "leaving the editor writes the name it was holding")
        guard let row = theRow(rows, "the committed batch") else { return }
        #expect(row.name == "Swim", "the write landed the name")
        #expect(row.persistedID != nil, "the store assigns ids on write")
    }

    @Test func editBatchNamePersists() async {
        let context = makeContext()
        commitNewBatch(context, on: day(1), name: "Swim")
        _ = await context.persistence.waitForWrites(1)

        // Reopen the stored row and rename it.
        var stored = await context.persistence.storedBatches(calendarID: 42)
        store_as_reloaded(&stored, using: context.store)
        context.store.send(.syncCalendar(calendarID: 42, batches: stored))
        guard reopen(stored, in: context, "the stored batch to reopen") else { return }
        context.editor.nameBinding.wrappedValue = "Swimming"
        context.store.send(.backTapped)

        let before = await context.persistence.writes.count
        _ = await context.persistence.waitForWrites(before + 1)
        let rows = await context.persistence.storedBatches(calendarID: 42)
        #expect(rows.count == 1, "renamed in place")
        #expect(rows.first?.name == "Swimming", "the rename reached the port, not just the registry")
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
        guard reopen(stored, in: context, "the stored batch to reopen") else { return }
        context.store.send(.backTapped)

        #expect(context.store.state.batches.count == 1)
    }

    @Test func removingAnEventFromABatchIsReflected() {
        let context = makeContext()
        context.store.send(.startNewBatch(on: day(1)))
        context.editor.nameBinding.wrappedValue = "Morning"
        context.editor.colorBinding.wrappedValue = .option1
        context.store.send(.toggleDay(day(2)))
        #expect(context.list.events.count == 2)

        removeFirstEvent(context, "an event to remove")
        context.store.send(.backTapped)

        #expect(context.store.state.batches.first?.events.count == 1)
    }

    @Test func recolouringABatchRewritesEveryEvent() {
        let context = makeContext()
        context.store.send(.startNewBatch(on: day(1)))
        context.store.send(.toggleDay(day(2)))
        context.editor.nameBinding.wrappedValue = "Morning"
        context.editor.colorBinding.wrappedValue = .option1
        context.store.send(.backTapped)

        let stored = context.store.state.batches
        context.store.send(.syncCalendar(calendarID: 42, batches: stored))
        guard reopen(stored, in: context, "the stored batch to reopen") else { return }
        context.editor.colorBinding.wrappedValue = .option3
        context.store.send(.backTapped)

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
        guard reopen(stored, in: context, "the stored batch to reopen") else { return }
        // Remove the only day: the batch is emptied. The row survives until the user leaves —
        // deleting on the removal itself would make a mis-tap on the final day destroy the
        // batch, and there is no undo for a batch anywhere in the app.
        removeFirstEvent(context, "an event to remove")
        #expect(!context.store.state.batches.isEmpty, "still there while the editor is open")
        context.store.send(.backTapped)

        #expect(context.store.state.batches.isEmpty, "an emptied batch leaves the calendar")
    }

    @Test func removingAnAnchorDayKeepsTheBatchWhenOtherDaysRemain() {
        let context = makeContext()
        context.store.send(.startNewBatch(on: day(1)))
        context.store.send(.toggleDay(day(2)))
        context.editor.nameBinding.wrappedValue = "Morning"
        context.editor.colorBinding.wrappedValue = .option1
        context.store.send(.backTapped)

        let stored = context.store.state.batches
        context.store.send(.syncCalendar(calendarID: 42, batches: stored))
        guard reopen(stored, in: context, "the stored batch to reopen") else { return }
        removeFirstEvent(context, "the anchor day's event") // the anchor day
        context.store.send(.backTapped)

        let batch = context.store.state.batches.first
        #expect(batch != nil, "a batch with a day left is still a batch")
        #expect(batch?.events.count == 1)
    }

    // MARK: - Round trips

    /// **One write, and it is the one that matters.**
    ///
    /// **Premise changed twice.** It used to be two: creating the batch wrote at once, and the
    /// *name* was debounced for 250 ms because typing is one edit rather than one write per
    /// keystroke — so this waited for two and read the second. Then the debounce went, because
    /// a write per keystroke was publishing a cache change per keystroke and each one came
    /// back as a `syncCalendar` that could roll the registry back mid-typing (see
    /// `staleReloadDuringDebouncedNameDoesNotDuplicate`, which is the bug that produced).
    ///
    /// What replaced it: **typing writes nothing, and the end of typing writes once.** The end
    /// of typing is the field resigning, the Done key, or leaving the editor — and
    /// `commitNewBatch` ends with Back, so the single write that carries the name is Back's.
    ///
    /// It is still safe, and safer than it was: the store outlives the editor and
    /// `flushBeforeLeavingCalendar` writes a name the editor never got to hand over, so there
    /// is no window where a typed name is lost on a calendar switch.
    @Test func leavingTheEditorRoundTripsTheNameThroughThePort() async throws {
        let context = makeContext()
        commitNewBatch(context, on: day(1), name: "Swim")
        let writes = await context.persistence.waitForWrites(1)

        // Read it back the way a reopen would.
        let readBack = try await context.persistence.eventBatches(calendarID: 42)
        #expect(writes == 1, "one write — creation and name are the same commit now, got \(writes)")
        #expect(readBack.count == 1)
        #expect(readBack.first?.name == "Swim", "the name is durable the moment the editor is left")
    }

    @Test func editingThenReFetchingReturnsTheUpdatedData() async {
        let context = makeContext()
        commitNewBatch(context, on: day(1), name: "Swim")
        _ = await context.persistence.waitForWrites(1)

        var stored = await context.persistence.storedBatches(calendarID: 42)
        store_as_reloaded(&stored, using: context.store)
        context.store.send(.syncCalendar(calendarID: 42, batches: stored))
        guard reopen(stored, in: context, "the stored batch to reopen") else { return }
        context.editor.nameBinding.wrappedValue = "Swimming"
        context.store.send(.backTapped)
        let before = await context.persistence.writes.count
        _ = await context.persistence.waitForWrites(before + 1)

        // A fresh model over the same storage sees the edit.
        let fresh = await Fixture.makeStore(
            batches: context.persistence.storedBatches(calendarID: 42),
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

    @Test func calendarUpdateAfterLeavingRetrievesTheCorrectBatches() async throws {
        let context = makeContext()
        commitNewBatch(context, on: day(1), name: "Swim")
        // Creation, then the debounced name — see the round-trip test above.
        _ = await context.persistence.waitForWrites(2)

        let readBack = try await context.persistence.eventBatches(calendarID: 42)
        #expect(readBack.map(\.name) == ["Swim"])
    }

    // MARK: - Helper

    /// The one row a read is expected to hold, or a recorded failure and `nil`.
    ///
    /// Every `[0]` in this file indexed a read that an earlier write was supposed to have
    /// filled. When the port comes back empty — a write that did not land, or a premise that
    /// has stopped holding — the subscript traps, and a trap in one test takes the whole bundle
    /// with it: the run reports a crash instead of the assertion that was actually wrong. That
    /// is not a near miss for this file, it is the entire cost of one unguarded index, and it
    /// is why the empty case has to be a message.
    ///
    /// Callers `guard let` on the result, so the suite reports "no rows where one was
    /// expected" once, naming the premise, rather than five subscript traps and nothing else.
    private func theRow(
        _ rows: [CalendarEventBatch],
        _ what: String,
        line: UInt = #line
    ) -> CalendarEventBatch? {
        guard let row = rows.first else {
            Issue.record(
                "Expected \(what), but the port held no rows",
                sourceLocation: SourceLocation(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1)
            )
            return nil
        }
        return row
    }

    /// Reopens the first stored row, or records that there is none.
    ///
    /// The `openBatch(id: stored[0].mergeKey)` this replaces was on six tests, and every one of
    /// them traps rather than failing when the port came back empty — which is the whole cost
    /// the `theRow` guard exists to remove. Returns `false` so the caller returns too, and the
    /// suite reports the premise once.
    @discardableResult
    private func reopen(
        _ stored: [CalendarEventBatch],
        in context: Context,
        _ what: String,
        line: UInt = #line
    ) -> Bool {
        guard let row = theRow(stored, what, line: line) else { return false }
        context.store.send(.openBatch(id: row.mergeKey))
        return true
    }

    /// Removes the batch's first event, or records that it has none.
    private func removeFirstEvent(
        _ context: Context,
        _ what: String,
        line: UInt = #line
    ) {
        guard let event = context.list.events.first else {
            Issue.record(
                "Expected \(what)",
                sourceLocation: SourceLocation(fileID: #fileID, filePath: #filePath, line: Int(line), column: 1)
            )
            return
        }
        context.list.remove(event)
    }

    /// Mimics what a reload does to a row: a *fresh* `pendingID`, because a DTO carries
    /// none. This is why §6.5 adoption has to be content-based — an id lookup can never
    /// match across a reload.
    ///
    /// It used to re-base every event to the start of its day as well, on the premise that
    /// `PCEventBatchAssembleUnitOfWork` normalised everything it staged. It does not any
    /// more — `applying` keeps the time of day so a picked time survives — so re-basing here
    /// would fabricate a difference between a row and its own reloaded copy, and hide exactly
    /// the class of bug this helper exists to be faithful about.
    private func store_as_reloaded(
        _ batches: inout [CalendarEventBatch],
        using store: PCEventSelectionManager
    ) {
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
                        date: $0.date,
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

        // Back, not Save: the checkmark is gone and every toggle above already wrote the
        // one-event row. This send is the re-anchor, not the commit.
        store.send(.backTapped)

        // The store executes effects through a chained `Task`, so nothing has happened by the
        // time `send` returns. And there are three writes in flight, not one: each `toggleDay`
        // merged and wrote as it went, which is the whole point — so `waitForWrites(1)` returns
        // after the *first* toggle and `writes.last` is then the four-event row. Waiting on a
        // count is the wrong tool when the interesting thing is the *content* of the final
        // write, so poll for that instead.
        let lastWrite = try #require(
            await persistence.waitForLastWrite { batches in
                guard let batch = batches.first else { return false }
                return batch.events.count == 1 && batch.persistedID == committed.persistedID
            },
            "no write carried the one-event row under the batch's own id"
        )
        let written = try #require(lastWrite.first)

        #expect(lastWrite.count == 1, "one batch is written")
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

        // …and the session has to be pointing at a day the batch is actually listed on,
        // because Back pops to the day list for `state.day`. `openBatch` set it to the row's
        // *first* event, which this edit removes, so without re-anchoring the pop returned to
        // a day list the batch was no longer on and it rendered empty — the reported AB, with
        // a perfectly correct batch behind it.
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
