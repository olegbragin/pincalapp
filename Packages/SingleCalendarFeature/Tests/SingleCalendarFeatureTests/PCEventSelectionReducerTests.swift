//
//  PCEventSelectionReducerTests.swift
//  SingleCalendarFeatureTests
//
//  Stage 5b's gate: §12.1. One test per row of the plan's §6.3 and §6.4 tables, plus the
//  cross-cutting rules — every action is covered, a rejected action is inert, a rejected
//  action emits nothing, and the reducer is a pure function of its two inputs.
//

import Testing
import Foundation
import CoreDomain
import DSKit
@testable import SingleCalendarFeature

@MainActor
@Suite("PCEventSelectionReducer Tests")
struct PCEventSelectionReducerTests {

    /// One fixed id standing in for every minted `pendingID`. It has to be a *constant*:
    /// substituting a fresh `UUID()` on each call would make the normaliser itself
    /// non-deterministic, and every purity check would fail for the wrong reason.
    private static let placeholderID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    // MARK: Fixtures

    /// The domain layer's only `Foundation.Calendar` owner.
    ///
    /// `PCCalendarDataProvider.init` forces the current time zone and locale, so a fixture
    /// calendar cannot pin them. Dates are built at midday UTC and the assertions are
    /// written to hold in whatever zone the tests run in.
    ///
    /// The one thing a UTC-pinned fixture cannot do is place an instant late in the day:
    /// 22:00 UTC is 01:00 of the *next* day east of UTC+2, so such a fixture silently
    /// crosses a day boundary and makes any day-granularity assertion vacuous. `evening(of:)`
    /// therefore builds its instant in the current time zone, matching the provider.
    private let provider = PCCalendarDataProvider()
    private let gregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let localGregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    private func day(_ dayOfMonth: Int, month: Int = 6, year: Int = 2026) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = dayOfMonth
        components.hour = 12
        return gregorian.date(from: components)!
    }

    private func evening(of d: Date) -> Date {
        localGregorian.date(bySettingHour: 22, minute: 0, second: 0, of: d)!
    }

    private func batch(
        _ name: String,
        on dayOfMonth: Int,
        id: Int64? = nil,
        color: String = "eventColorOption1",
        eventName: String = "Event"
    ) -> CalendarEventBatch {
        CalendarEventBatch(
            persistedID: id,
            name: name,
            colorName: color,
            events: [CalendarEvent(name: eventName, date: day(dayOfMonth), colorName: color)]
        )
    }

    /// Zeroes every `pendingID` so two runs of an action can be compared.
    ///
    /// The reducer mints a fresh `pendingID` for any action that creates an assembly, so
    /// two runs differ in exactly that one place. That is the one part of the transition
    /// that is not a function of its inputs, and it is a deliberate one: `pendingID` *is*
    /// session identity, so a new batch needs a new one.
    private func normalized(_ state: PCEventSelectionState) -> PCEventSelectionState {
        var copy = state
        copy.batches = copy.batches.map(normalized)
        copy.assembly = copy.assembly.map(normalized)
        copy.eventDraft = copy.eventDraft.map { $0.with(pendingID: Self.placeholderID) }
        return copy
    }

    private func normalized(_ assembler: PCEventBatchAssembleUnitOfWork) -> PCEventBatchAssembleUnitOfWork {
        // Via the public factory: `init(batch:origin:)` is private by design. The origin
        // is normalised too, since it carries a minted UUID in the `.existing` case.
        PCEventBatchAssembleUnitOfWork
            .existing(normalized(assembler.batch))
            .adopting(persistedID: assembler.adoptedPersistedID)
    }

    private func normalized(_ batch: CalendarEventBatch) -> CalendarEventBatch {
        CalendarEventBatch(
            pendingID: PCEventSelectionReducerTests.placeholderID,
            persistedID: batch.persistedID,
            name: batch.name,
            colorName: batch.colorName,
            events: batch.events.map { $0.with(pendingID: PCEventSelectionReducerTests.placeholderID) }
        )
    }

    /// A state mid-session: a committed calendar and one batch on the 1st, nothing staged.
    private func session(
        batches: [CalendarEventBatch]? = nil,
        calendarID: Int64 = 42
    ) -> PCEventSelectionState {
        var state = PCEventSelectionState(dataProvider: provider)
        state.calendarID = calendarID
        state.batches = batches ?? [batch("morning", on: 1, id: 7)]
        // Derive, never hand-write: `dayEventColors` is a derived field, and a fixture that
        // fills it in by a different route builds a state the reducer cannot emit. That
        // shows up as the rejected-action contract breaking — a guard that correctly changes
        // nothing still "changes" the state, because the payload disagrees with what the
        // state implies. `derivedDayEventColors` is the same derivation the reducer uses.
        state.dayEventColors = state.derivedDayEventColors
        return state
    }

    /// A named, coloured assembly on the given day — past `canSave`.
    private func editing(_ state: PCEventSelectionState, on dayOfMonth: Int) -> PCEventSelectionState {
        var next = state
        next.day = day(dayOfMonth)
        next.assembly = PCEventBatchAssembleUnitOfWork
            .new(anchor: day(dayOfMonth), colorName: "", using: provider)
            .renaming("edited")
            .recoloring(.option2)
        next.stage = .batchEditor
        next.dayEventColors = next.derivedDayEventColors
        return next
    }

    private func showingDayList(_ state: PCEventSelectionState, on d: Date) -> PCEventSelectionState {
        var next = state
        next.day = d
        next.stage = .dayList(day: d)
        next.dayEventColors = next.derivedDayEventColors
        return next
    }

    /// A state mid-multi-select, with the session's batch built the way the reducer builds it.
    ///
    /// The assembly is derived rather than omitted because it is now load-bearing: it holds
    /// the batch's identity, and a fixture that set only `multiSelectDays` would describe a
    /// session the reducer cannot produce — the same trap as hand-writing `dayEventColors`.
    private func multiSelecting(
        _ state: PCEventSelectionState,
        days: [Date],
        color: PCColorOption? = .option1
    ) -> PCEventSelectionState {
        var next = state
        next.multiSelectMode = true
        next.multiSelectDays = days
        next.multiSelectColor = color
        if let color, !days.isEmpty {
            var assembly = PCEventBatchAssembleUnitOfWork.new(
                anchor: days.min()!,
                colorName: color.colorName,
                using: provider
            )
            // One assembly for the session, built by toggling in the remaining days — the
            // same path the reducer takes, so the identity matches rather than being faked.
            for day in days.dropFirst() {
                assembly = assembly.toggling(day: day, using: provider)
            }
            next.multiSelectAssembly = assembly
        }
        next.dayEventColors = next.derivedDayEventColors
        return next
    }

    /// A state with the event editor open and a named draft in it.
    private func stagedSession() -> PCEventSelectionState {
        let editing = editing(session(batches: []), on: 2)
        guard let event = editing.assembly?.batch.events.first else { return editing }
        let opened = pcEventSelectionReducer(editing, .openEvent(pendingID: event.pendingID))
        return pcEventSelectionReducer(opened, .setEventName("draft"))
    }

    private func reduce(
        _ state: PCEventSelectionState,
        _ action: PCEventSelectionAction
    ) -> (next: PCEventSelectionState, effects: [PCEventSelectionEffect]) {
        let next = pcEventSelectionReducer(state, action)
        return (next, pcEventSelectionEffects(action, state, next))
    }

    /// The same rows as they come back from the database.
    ///
    /// Rebuilt rather than reused, because the reload is *not* a copy: `RootMapper` mints a
    /// fresh `pendingID` for every row on every load and only an id the database assigned
    /// survives. Passing the original arrays through would leave `pendingID` intact and hide
    /// the entire mechanism these tests are about — which is that a staged row and its own
    /// persisted copy can never be recognised by key, only by content.
    private func reloaded(_ rows: [CalendarEventBatch], from firstID: Int64 = 100) -> [CalendarEventBatch] {
        rows.enumerated().map { offset, row in
            CalendarEventBatch(
                persistedID: row.persistedID ?? firstID + Int64(offset),
                name: row.name,
                colorName: row.colorName,
                events: row.events.map {
                    CalendarEvent(
                        persistedID: $0.persistedID ?? firstID + Int64(offset) * 1_000,
                        name: $0.name,
                        date: $0.date,
                        colorName: $0.colorName
                    )
                }
            )
        }
    }

    // MARK: - Entry

    @Test("ensureAssemblyStarted is inert whether or not there is an assembly")
    func ensureAssemblyStartedInert() {
        let idle = session()
        #expect(reduce(idle, .ensureAssemblyStarted).next == idle)

        let editing = editing(idle, on: 5)
        #expect(reduce(editing, .ensureAssemblyStarted).next == editing)
    }

    @Test("Tapping an empty day starts a batch editor and asks for a push")
    func dayTappedEmptyDay() {
        let state = session()
        let (next, effects) = reduce(state, .dayTappedInCalendar(day(4)))

        #expect(next.stage == .batchEditor)
        #expect(next.assembly != nil)
        #expect(next.day == day(4))
        #expect(next.scrollAnchor == day(4))
        #expect(next.editorYear == nil)
        #expect(
            next.assembly?.canSave == true,
            "a merely-tapped day arrives named and coloured, so it is written without any editing"
        )
        #expect(next.navigationRequest?.target == .pushBatchEditor)
        // Was "staging is not a write". Tapping a day now writes the batch immediately, so
        // there is a row on disk before the editor has been touched — tapping a day is the
        // decision to add a batch, and it has everything needed to make one.
        #expect(effects.count == 1, "tapping an empty day writes the new batch at once")
    }

    @Test("Tapping a day that has batches opens the day list instead")
    func dayTappedWithBatches() {
        let state = session()
        let (next, _) = reduce(state, .dayTappedInCalendar(day(1)))

        #expect(next.stage == .dayList(day: day(1)))
        #expect(next.assembly == nil)
        #expect(next.navigationRequest?.target == .pushDayList)
    }

    @Test("A day tap in multi-select mode toggles the day and opens nothing")
    func dayTappedMultiSelect() {
        let state = multiSelecting(session(), days: [])

        let first = reduce(state, .dayTappedInCalendar(day(4))).next
        #expect(first.multiSelectDays.count == 1)
        #expect(provider.isSameDay(first.multiSelectDays[0], day(4)))
        #expect(first.navigationRequest == nil, "multi-select does not navigate")
        #expect(first.stage == .idle)

        let second = reduce(first, .dayTappedInCalendar(day(4))).next
        #expect(second.multiSelectDays.isEmpty, "tapping the same day again deselects it")
    }

    @Test("A multi-select day tap is day-granular, not instant-granular")
    func dayTappedMultiSelectIsDayGranular() {
        let state = multiSelecting(session(), days: [])
        let after = reduce(state, .dayTappedInCalendar(evening(of: day(4)))).next
        #expect(after.multiSelectDays.count == 1)
        #expect(
            provider.isSameDay(after.multiSelectDays[0], day(4)),
            "the stored value must name the same day the tap did"
        )

        let toggledOff = reduce(after, .dayTappedInCalendar(day(4))).next
        #expect(
            toggledOff.multiSelectDays.isEmpty,
            "22:00 and midday name the same day, so the second tap must deselect"
        )
    }

    @Test("startNewBatch stages an assembly on the given day")
    func startNewBatch() {
        let state = session()
        let (next, effects) = reduce(state, .startNewBatch(on: day(9)))

        #expect(next.stage == .batchEditor)
        #expect(next.day == day(9))
        #expect(next.scrollAnchor == day(9))
        #expect(next.navigationRequest?.target == .pushBatchEditor)
        #expect(effects.count == 1, "the plus button writes its new batch at once too")
    }

    @Test("openBatch stages the batch it found and asks for a push")
    func openBatch() {
        let target = batch("morning", on: 1, id: 7)
        let (next, _) = reduce(session(batches: [target]), .openBatch(id: target.mergeKey))

        #expect(next.stage == .batchEditor)
        #expect(next.assembly?.batch.pendingID == target.pendingID)
        #expect(next.day == target.date)
        #expect(next.scrollAnchor == target.date)
        #expect(next.navigationRequest?.target == .pushBatchEditor)
    }

    /// The regression that made a card tap do nothing.
    ///
    /// `pendingID` is session identity and a DTO carries none, so every row is re-minted on
    /// every load — and the model re-syncs on every calendar write, so a write from
    /// anywhere re-mints the row a card on screen was drawn from. Opening by `pendingID`
    /// then missed, the action was rejected, and the tap was dropped with nothing logged.
    /// `mergeKey` survives, because the persisted id does.
    @Test("A reload re-mints every pendingID, and a card drawn before it still opens its row")
    func openBatchSurvivesAReload() throws {
        let drawn = twoDayBatch()
        // The same row as a DTO round trip produces it: same persisted id, same events,
        // brand-new `pendingID` because a DTO has nowhere to carry the old one.
        let reloaded = CalendarEventBatch(
            persistedID: drawn.persistedID,
            name: drawn.name,
            colorName: drawn.colorName,
            events: drawn.events
        )
        #expect(drawn.pendingID != reloaded.pendingID, "a reload re-mints session identity")
        #expect(
            [reloaded].first(where: { $0.pendingID == drawn.pendingID }) == nil,
            "the lookup the old code performed matched nothing — which is why the tap was dropped"
        )

        let next = reduce(session(batches: [reloaded]), .openBatch(id: drawn.mergeKey)).next

        #expect(
            next.assembly?.batch.persistedID == drawn.persistedID,
            "the card named the row by its durable id, so the reload did not lose it"
        )
        #expect(next.navigationRequest?.target == .pushBatchEditor)
    }

    @Test("openBatch with an unknown id is rejected")
    func openBatchUnknown() {
        let state = session()
        #expect(reduce(state, .openBatch(id: .pending(UUID()))).next == state)
        #expect(reduce(state, .openBatch(id: .persisted(999))).next == state, "no such row")
    }

    @Test("Back from the event editor drops the draft and returns to the batch editor")
    func backFromEventEditor() {
        var state = editing(session(), on: 1)
        state.eventDraft = CalendarEvent(name: "draft", date: day(1), colorName: "eventColorOption2")
        state.stage = .eventEditor(batchPendingID: UUID(), eventPendingID: UUID())

        let (next, effects) = reduce(state, .backTapped)

        #expect(next.eventDraft == nil)
        #expect(next.stage == .batchEditor)
        #expect(next.assembly != nil, "the batch being edited is still staged")
        #expect(next.navigationRequest?.target == .pop)
        #expect(effects.isEmpty)
    }

    /// Leaving the batch editor is navigation, not a commit.
    ///
    /// **Premise changed, twice.** This used to say "Back discards the staged edit and returns
    /// to the day list", with the parenthetical "save is what commits". Both halves were false
    /// and the parenthetical was the load-bearing wrong one: `editing` merged the row and wrote
    /// it as the edit was made, so there was never a staged edit to discard and nothing for a
    /// later Save to commit. The checkmark existed to make the feature look like it had a save
    /// step; removing it leaves Back as the only exit, and Back has nothing to do.
    ///
    /// What Back does still do is publish whatever the assembly holds, so an edit that reached
    /// it cannot be lost on the way out. In the real flow `editing` has already merged that row
    /// and this is a no-op; the `editing` fixture stages an assembly the registry does not
    /// describe, so here it is the difference between the edit surviving and vanishing. The
    /// no-write case is pinned on a production-shaped state in `backCommitsAndCloses`.
    @Test("Back from the batch editor publishes the staged row and pops to the day list")
    func backFromBatchEditor() {
        let (next, _) = reduce(editing(session(), on: 1), .backTapped)

        #expect(next.assembly == nil, "the editor is closed")
        #expect(
            next.batches.contains { $0.name == "edited" },
            "the staged edit reached the registry rather than being dropped"
        )
        // Compared as a *day*, not as an instant. `day(1)` is noon UTC and a placeholder sits
        // at the start of its day, so the two denote the same day by different instants —
        // `dayBatches` matches with `isSameDay`, and only the day is the contract.
        let dayList = try! #require(next.stage.asDayList)
        #expect(
            provider.isSameDay(dayList, day(1)),
            "returns to the day list for the day the batch is on, got \(dayList)"
        )
        #expect(next.navigationRequest?.target == .pop)
    }

    @Test("Back from the batch editor with no day falls back to idle")
    func backFromBatchEditorNoDay() {
        var state = session()
        state.assembly = PCEventBatchAssembleUnitOfWork.new(anchor: day(3), colorName: "", using: provider)
        state.stage = .batchEditor

        #expect(reduce(state, .backTapped).next.stage == .idle)
    }

    @Test("Back from the day list goes idle and forgets the day")
    func backFromDayList() {
        let state = showingDayList(session(), on: day(1))
        let (next, _) = reduce(state, .backTapped)

        #expect(next.stage == .idle)
        #expect(next.day == nil)
        #expect(next.assembly == nil)
        #expect(next.navigationRequest?.target == .pop)
    }

    @Test("Back while idle does nothing")
    func backWhileIdle() {
        let state = session()
        #expect(reduce(state, .backTapped).next == state)
    }

    @Test("Close clears the session, rebuilds committed markers, and unwinds to the root")
    func closeTapped() {
        let (next, effects) = reduce(editing(session(), on: 1), .closeTapped)

        #expect(next.stage == .idle)
        #expect(next.day == nil)
        #expect(next.assembly == nil)
        #expect(next.eventDraft == nil)
        #expect(next.navigationRequest?.target == .popToCalendarRoot)
        #expect(
            next.dayEventColors[provider.startOfDay(for: day(1))] == ["eventColorOption1"],
            "markers go back to the committed colours, not the staged ones"
        )
        #expect(effects.isEmpty, "close discards; it does not write")
    }

    @Test("cancelTapped behaves exactly as closeTapped")
    func cancelTapped() {
        let state = editing(session(), on: 1)
        #expect(reduce(state, .closeTapped).next == reduce(state, .cancelTapped).next)
    }

    @Test("navigationRequestHandled clears the pending request")
    func navigationRequestHandled() {
        let requested = reduce(session(), .dayTappedInCalendar(day(4))).next
        #expect(requested.navigationRequest != nil)

        let handled = reduce(requested, .navigationRequestHandled).next

        #expect(handled.navigationRequest == nil)
        #expect(handled.stage == requested.stage, "handling a request is not a transition")
    }

    @Test("A second navigation on a state that already has one pending gets a new id")
    func navigationIdsIncrement() {
        let state = session()
        let first = reduce(state, .dayTappedInCalendar(day(4))).next
        let second = reduce(first, .startNewBatch(on: day(6))).next

        #expect(first.navigationRequest?.id == 1)
        #expect(second.navigationRequest?.id == 2, "a second request on a state that has one pending")

        // After the view handles it, the count starts over — which is all the id has to do.
        let handled = reduce(second, .navigationRequestHandled).next
        #expect(handled.navigationRequest == nil)
        #expect(reduce(handled, .dayTappedInCalendar(day(4))).next.navigationRequest?.id == 1)
    }

    // MARK: - Batch editor

    @Test("setBatchName renames the staged assembly")
    func setBatchName() {
        let (next, effects) = reduce(editing(session(), on: 1), .setBatchName("renamed"))

        #expect(next.assembly?.batch.name == "renamed")
        // Edits persist as they are made, so a rename is a write. This assertion used to be
        // `effects.isEmpty`, which was the old contract: a rename staged and nothing landed.
        #expect(effects.count == 1, "renaming writes through, with no Save in between")
    }

    @Test("setBatchColor recolours the assembly and moves the markers with it")
    func setBatchColor() {
        var state = editing(session(), on: 1)
        // Day 3 is in neither `batches` nor the assembly, so its marker can only come from
        // the staged batch — which is the whole point of the assertion.
        state.assembly = state.assembly?.toggling(day: day(3), using: provider)
        let (next, effects) = reduce(state, .setBatchColor(.option3))

        #expect(next.assembly?.batch.colorName == PCColorOption.option3.colorName)
        #expect(
            next.dayEventColors[provider.startOfDay(for: day(3))] == ["eventColorOption3"],
            "markers follow the staged colour, for a day that is not in batches at all"
        )
        #expect(effects.count == 1, "recolouring writes through — it rewrites every event")
    }

    @Test("toggleDay adds a day to the assembly and to the markers")
    func toggleDay() {
        let (next, effects) = reduce(editing(session(), on: 1), .toggleDay(day(5)))

        #expect(next.assembly?.batch.events.count == 2)
        #expect(next.dayEventColors[provider.startOfDay(for: day(5))] != nil)
        #expect(effects.count == 1, "adding a day writes the batch at once")
    }

    @Test("toggleDay is refused outside the batch editor")
    func toggleDayWrongStage() {
        var state = session()
        state.assembly = PCEventBatchAssembleUnitOfWork.new(anchor: day(1), colorName: "", using: provider)
        state.stage = .dayList(day: day(1))
        state.dayEventColors = state.derivedDayEventColors

        #expect(reduce(state, .toggleDay(day(5))).next == state)
    }

    @Test("Tapping an empty day marks it, and backing out takes the marker with it")
    func emptyDayTapThenBackClearsMarker() {
        // Reported as: the batch editor opens with the tapped day unmarked, and pressing back
        // leaves a marker behind for an event that was never written.
        let empty = session(batches: [])

        let tapped = reduce(empty, .dayTappedInCalendar(day(9))).next
        #expect(tapped.assembly != nil, "tapping an empty day stages an assembly")
        #expect(tapped.stage == .batchEditor)
        #expect(
            tapped.dayEventColors[provider.startOfDay(for: day(9))] != nil,
            "the staged event must be marked in the editor's calendar"
        )

        let back = reduce(tapped, .backTapped).next
        #expect(back.assembly == nil, "back closes the editor")
        // The marker used to be expected to vanish here, because tapping a day staged a
        // batch that Back threw away. Tapping a day now writes the batch, so the marker is
        // the truth: the event exists, and leaving the editor does not unmake it.
        #expect(
            back.dayEventColors[provider.startOfDay(for: day(9))] != nil,
            "the batch was written when the day was tapped, so the marker is real"
        )
    }

    @Test("Starting a new batch from the add button marks the day, and cancel leaves it written")
    func startNewBatchThenCancelClearsMarker() {
        let empty = session(batches: [])

        let started = reduce(empty, .startNewBatch(on: day(9))).next
        #expect(started.stage == .batchEditor)
        #expect(
            started.dayEventColors[provider.startOfDay(for: day(9))] != nil,
            "the staged event must be marked in the editor's calendar"
        )

        // Cancel now only closes the editor. The test name said "cancel takes it away" and
        // the marker did go — but the batch behind it had been written when the plus button
        // was tapped, so what vanished was the marker for a row that was still on the day.
        // Closing an editor is not undoing the edit that led to it.
        let cancelled = reduce(started, .cancelTapped).next
        #expect(
            cancelled.dayEventColors[provider.startOfDay(for: day(9))] != nil,
            "the batch was written on creation, so the marker outlives the editor"
        )
        #expect(cancelled.assembly == nil, "but the editor is closed")
    }

    @Test("removeEvent drops the event and its marker")
    func removeEvent() {
        let state = editing(session(), on: 1)
        let pendingID = try! #require(state.assembly?.batch.events.first?.pendingID)
        let (next, effects) = reduce(state, .removeEvent(pendingID: pendingID))

        #expect(try! #require(next.assembly).batch.events.isEmpty)
        #expect(
            next.dayEventColors[provider.startOfDay(for: day(1))] == ["eventColorOption1"],
            "the committed batch on that day is untouched, so its marker remains"
        )
        #expect(effects.isEmpty)
    }

    /// A committed batch holding an event on the 10th and one on the 12th.
    ///
    /// The shape the UI suite's seeded calendar has, and the shape the marker bug needs: a
    /// row the user can open, and a day that two copies of the same row would both claim.
    private func twoDayBatch(id: Int64 = 7) -> CalendarEventBatch {
        CalendarEventBatch(
            persistedID: id,
            name: "Women Cycle",
            colorName: "eventColorOption1",
            events: [
                CalendarEvent(name: "Event1", date: day(10), colorName: "eventColorOption1"),
                CalendarEvent(name: "Event1", date: day(12), colorName: "eventColorOption1")
            ]
        )
    }

    @Test("Opening an existing batch does not double-count the day both copies of it hold")
    func openBatchDoesNotDoubleCountTheSharedDay() {
        let committed = twoDayBatch()
        let next = reduce(session(batches: [committed]), .openBatch(id: committed.mergeKey)).next

        #expect(
            next.dayEventColors[provider.startOfDay(for: day(12))] == ["eventColorOption1"],
            "the staged copy IS the committed row, so the shared day holds one event, not two"
        )
    }

    @Test("Removing an event from an opened existing batch unmarks the day it emptied")
    func removeEventFromOpenedBatchUnmarksTheDay() {
        let committed = twoDayBatch()
        let opened = reduce(session(batches: [committed]), .openBatch(id: committed.mergeKey)).next
        let pendingID = try! #require(opened.assembly?.batch.events.first?.pendingID)

        let next = reduce(opened, .removeEvent(pendingID: pendingID)).next

        #expect(
            next.dayEventColors[provider.startOfDay(for: day(10))] == nil,
            "the batch holds no event on the 10th any more, so its marker has to go"
        )
        #expect(
            next.dayEventColors[provider.startOfDay(for: day(12))] == ["eventColorOption1"],
            "the surviving event still marks the 12th, and marks it once"
        )
    }

    // MARK: - Event editor

    @Test("openEvent carries both ids into the stage")
    func openEvent() {
        let state = editing(session(), on: 1)
        let event = try! #require(state.assembly?.batch.events.first)
        let (next, effects) = reduce(state, .openEvent(pendingID: event.pendingID))

        #expect(next.eventDraft == event)
        #expect(next.stage == .eventEditor(
            batchPendingID: try! #require(state.assembly?.batch.pendingID),
            eventPendingID: event.pendingID
        ))
        #expect(next.navigationRequest?.target == .pushEventEditor)
        #expect(effects.isEmpty)
    }

    @Test("openEvent with an unknown id is rejected")
    func openEventUnknown() {
        let state = editing(session(), on: 1)
        #expect(reduce(state, .openEvent(pendingID: UUID())).next == state)
    }

    @Test("setEventName, setEventDate and setEventColor edit the draft only")
    func editEventDraft() {
        let base = editing(session(), on: 1)
        let event = try! #require(base.assembly?.batch.events.first)
        let opened = reduce(base, .openEvent(pendingID: event.pendingID)).next

        let named = reduce(opened, .setEventName("n")).next
        #expect(named.eventDraft?.name == "n")

        let dated = reduce(named, .setEventDate(day(8))).next
        #expect(provider.isSameDay(try! #require(dated.eventDraft).date, day(8)))

        let colored = reduce(dated, .setEventColor(.option4)).next
        #expect(colored.eventDraft?.colorName == PCColorOption.option4.colorName)
        let assembly = try! #require(base.assembly)
        let stagedEvent = try! #require(assembly.batch.events.first)
        #expect(
            stagedEvent.name == PCEventBatchAssembleUnitOfWork.defaultEventName,
            "the staged event keeps its default name until the draft is saved"
        )
    }

    @Test("Event edits without a draft are rejected")
    func editEventDraftWithoutDraft() {
        let state = editing(session(), on: 1)
        #expect(reduce(state, .setEventName("n")).next == state)
        #expect(reduce(state, .setEventDate(day(8))).next == state)
        #expect(reduce(state, .setEventColor(.option1)).next == state)
    }

    /// Leaving the event editor drops the draft and keeps the edit.
    ///
    /// **Premise changed.** `saveEventTapped` used to be the way out of this editor: it
    /// re-applied the draft to the assembly "so the edit is not lost" and popped. The
    /// checkmark that sent it is gone, Back is the exit, and the re-apply was never load-bearing
    /// — `persistEventDraft` had already folded every keystroke in. What is left to pin is the
    /// reason Back can be trusted: the batch holds the edit while the editor is still open.
    @Test("Backing out of the event editor keeps the edit and drops the draft")
    func backOutOfEventEditorKeepsTheEdit() {
        let base = editing(session(), on: 1)
        let event = try! #require(base.assembly?.batch.events.first)
        var state = reduce(base, .openEvent(pendingID: event.pendingID)).next
        state = reduce(state, .setEventName("Edited")).next

        let (next, effects) = reduce(state, .backTapped)

        #expect(
            try! #require(next.assembly).batch.events.contains { $0.name == "Edited" },
            "the batch had it before Back was pressed, so dropping the draft loses nothing"
        )
        #expect(next.eventDraft == nil)
        #expect(next.stage == .batchEditor)
        #expect(next.navigationRequest?.target == .pop)
        #expect(effects.isEmpty, "the write happened when the name was typed")
    }

    @Test("discardEventTapped drops the draft and pops")
    func discardEventTapped() {
        let base = editing(session(), on: 1)
        let event = try! #require(base.assembly?.batch.events.first)
        var opened = reduce(base, .openEvent(pendingID: event.pendingID)).next
        opened = reduce(opened, .setEventName("throwaway")).next

        let (next, effects) = reduce(opened, .discardEventTapped)

        #expect(next.eventDraft == nil)
        #expect(next.stage == .batchEditor)
        let assembly = try! #require(base.assembly)
        let kept = try! #require(assembly.batch.events.first)
        #expect(
            kept.name == PCEventBatchAssembleUnitOfWork.defaultEventName,
            "the edit is gone: the batch still holds the default-named event"
        )
        #expect(next.navigationRequest?.target == .pop)
        #expect(effects.isEmpty)
    }

    // MARK: - Persistence

    /// §16, the reported bug, at its actual cause.
    ///
    /// Opening a batch sets `day` from the row's *first* event. An edit that removes that
    /// event leaves the session pointing at a day the batch is no longer listed on, so the
    /// pop after leaving returns to an empty day list. Nothing is lost and nothing errors —
    /// which is exactly why it was reported as "the batch list is empty" and went looking for a
    /// deletion that never happened.
    ///
    /// The re-anchoring moved from `saveTapped` to `backTapped` along with the button. It is
    /// the same fix and it is still needed: Back is now the only pop out of this editor.
    @Test("Leaving re-anchors the session on the day the batch is on, not the one it was opened on")
    func backReanchorsOnTheRowsDay() {
        // A committed batch on the 10th, 11th, 12th and 13th.
        let committed = CalendarEventBatch(
            persistedID: 7,
            name: "Window",
            colorName: "eventColorOption1",
            events: (10...13).map { CalendarEvent(name: "Event", date: day($0), colorName: "eventColorOption1") }
        )
        let opened = reduce(session(batches: [committed]), .openBatch(id: committed.mergeKey)).next
        #expect(
            provider.isSameDay(try! #require(opened.day), day(10)),
            "setup: the session opens on the row's first day"
        )

        // Remove the 10th, 11th and 12th, leaving the 13th — §16's step 6.
        var staged = opened
        for d in [10, 11, 12] {
            staged = reduce(staged, .toggleDay(day(d))).next
        }
        #expect(try! #require(staged.assembly?.batch).events.count == 1, "setup: one event left")

        let (next, _) = reduce(staged, .backTapped)

        #expect(
            provider.isSameDay(try! #require(next.day), day(13)),
            "the session must follow the batch to the 13th, not stay on the 10th it was opened on"
        )
        #expect(
            next.stage.asDayList.map { provider.isSameDay($0, day(13)) } == true,
            "and the pop must return to the 13th's list, which is where the batch now is"
        )
        #expect(
            next.dayBatches.count == 1,
            "so that list is not empty: \(next.dayBatches.count) batches"
        )
    }

    /// An emptied batch is deleted by leaving the editor — and only by leaving.
    ///
    /// This replaces `saveTappedEmptied`, which asserted the same thing about a button. What
    /// changed is *when*, and the difference is the whole reason the behaviour is defensible:
    /// the row survives every removal, so a mis-tap on the final remaining day is undone by
    /// tapping it again, and there is no undo for a batch anywhere in the app. Deleting on the
    /// removal would have made an accidental tap unrecoverable in exchange for consistency.
    @Test("Leaving an emptied batch editor deletes the row and unwinds to the root")
    func backFromEmptiedBatchEditorDeletes() {
        // Built through `startNewBatch` rather than the `editing` fixture, because the claim
        // being made is about a row that is *in the registry* — the fixture stages an assembly
        // without merging it, which the reducer cannot produce and which would make "the row
        // outlives the removal" vacuous.
        let created = reduce(session(batches: []), .startNewBatch(on: day(1))).next
        let pendingID = try! #require(created.assembly?.batch.events.first?.pendingID)
        #expect(created.batches.count == 1, "setup: creation wrote the row")

        let emptied = reduce(created, .removeEvent(pendingID: pendingID)).next

        // Still there while the editor is open — that is the recoverable window.
        #expect(emptied.batches.count == 1, "the row outlives the removal")
        #expect(emptied.assembly?.batch.events.isEmpty == true)
        #expect(
            reduce(emptied, .removeEvent(pendingID: pendingID)).effects.isEmpty,
            "and nothing was written for the empty state — there is no row to write"
        )

        let (next, effects) = reduce(emptied, .backTapped)

        #expect(next.assembly == nil)
        #expect(next.stage == .idle)
        #expect(next.day == nil)
        #expect(next.didSave)
        #expect(next.batches.isEmpty, "the emptied row left the registry")
        #expect(
            next.dayEventColors == PCCalendarMarkerProjector.colorsByDay(from: next.batches, using: provider),
            "the row left the registry, so the markers are restated without it — the batch's days stop being marked"
        )
        #expect(
            next.navigationRequest?.target == .popToCalendarRoot,
            "not to the day list: the batch that list would have shown is the one just deleted"
        )
        #expect(effects == [.writeCalendar(calendarID: 42, numberOfColumns: 3, batches: next.batches)])
    }

    /// A batch that is merely *unwritable* — no colour — is not emptied, so leaving must not
    /// delete it. Colour and emptiness are different failures and the branch is on emptiness.
    @Test("Leaving an uncoloured but non-empty batch does not delete it")
    func backFromUnwritableBatchKeepsIt() {
        var state = session()
        state.assembly = PCEventBatchAssembleUnitOfWork.new(anchor: day(3), colorName: "", using: provider)
        state.stage = .batchEditor
        state.day = day(3)
        state.dayEventColors = state.derivedDayEventColors

        let (next, effects) = reduce(state, .backTapped)

        #expect(next.assembly == nil, "it does close the editor")
        #expect(next.batches.count == 1, "but the row it created is still there")
        #expect(next.stage == .dayList(day: day(3)))
        #expect(effects.isEmpty)
    }

    @Test("deleteBatches removes the rows, writes, and unwinds when the day empties")
    func deleteBatches() {
        let state = showingDayList(session(), on: day(1))
        let (next, effects) = reduce(state, .deleteBatches(state.batches))

        #expect(next.batches.isEmpty)
        #expect(next.dayEventColors.isEmpty)
        #expect(next.navigationRequest?.target == .popToCalendarRoot)
        #expect(effects == [.writeCalendar(calendarID: 42, numberOfColumns: 3, batches: [])])
    }

    @Test("deleteBatches on a day with other batches left does not unwind")
    func deleteBatchesDayNotEmptied() {
        let state = showingDayList(
            session(batches: [batch("a", on: 1, id: 7), batch("b", on: 1, id: 8)]),
            on: day(1)
        )

        let (next, _) = reduce(state, .deleteBatches([state.batches[0]]))

        #expect(next.batches.count == 1)
        #expect(next.navigationRequest == nil, "something is still on the day")
    }

    @Test("deleteBatches for rows that are not there changes nothing and writes nothing")
    func deleteBatchesUnknown() {
        let state = session()
        let (next, effects) = reduce(state, .deleteBatches([batch("ghost", on: 30, id: 999)]))

        #expect(next.batches == state.batches)
        #expect(effects.isEmpty)
    }

    @Test("The first syncCalendar establishes the calendar and is not rejected by the id guard")
    func syncCalendarFirst() {
        let state = PCEventSelectionState(dataProvider: provider)
        #expect(state.calendarID == 0, "the id guard has to tolerate the pre-session value")

        let incoming = [batch("loaded", on: 2, id: 11)]
        let (next, effects) = reduce(state, .syncCalendar(calendarID: 42, batches: incoming))

        #expect(next.calendarID == 42)
        #expect(next.batches == incoming)
        #expect(effects.isEmpty, "loading is a read")
    }

    @Test("A sync for a different calendar is ignored once one is established")
    func syncCalendarWrongCalendar() {
        let state = session()
        let (next, effects) = reduce(state, .syncCalendar(calendarID: 99, batches: [batch("other", on: 3, id: 1)]))

        #expect(next == state)
        #expect(effects.isEmpty)
    }

    @Test("syncCalendar adopts the persisted id of a staged batch that came back")
    func syncCalendarAdopts() {
        var state = session(batches: [])
        state.assembly = stagedBatch()
        state.stage = .batchEditor

        // What comes back from the store after our own write: same name, colour, day and
        // event — including the event's *default* name, because that is what was persisted
        // — but now with a real id and a fresh pendingID, since a DTO carries none.
        let incoming = [batch("morning", on: 2, id: 77, eventName: PCEventBatchAssembleUnitOfWork.defaultEventName)]

        let (next, effects) = reduce(state, .syncCalendar(calendarID: 42, batches: incoming))

        #expect(next.assembly?.adoptedPersistedID == 77, "so the next commit updates row 77")
        #expect(next.assembly?.resolved()?.persistedID == 77)
        #expect(
            effects == [.writeCalendar(calendarID: 42, numberOfColumns: 3, batches: incoming)],
            "the reassignment has to land, so this sync does write"
        )
    }

    @Test("A reload that adopts the staged row does not double-count the day both copies hold")
    func syncCalendarAdoptionDoesNotDoubleCount() {
        var state = session(batches: [])
        state.assembly = stagedBatch()
        state.stage = .batchEditor

        let incoming = [batch("morning", on: 2, id: 77, eventName: PCEventBatchAssembleUnitOfWork.defaultEventName)]

        let next = reduce(state, .syncCalendar(calendarID: 42, batches: incoming)).next

        #expect(
            next.dayEventColors[provider.startOfDay(for: day(2))] == ["eventColorOption1"],
            "the adopted staged row and the row it came back as are one batch, not two"
        )
    }

    @Test("syncCalendar does not re-adopt an assembly that already has an id")
    func syncCalendarAdoptsOnce() {
        var state = session(batches: [])
        state.assembly = stagedBatch().adopting(persistedID: 5)
        state.stage = .batchEditor

        let (next, effects) = reduce(
            state,
            .syncCalendar(calendarID: 42, batches: [batch("morning", on: 2, id: 77, eventName: PCEventBatchAssembleUnitOfWork.defaultEventName)])
        )

        #expect(next.assembly?.adoptedPersistedID == 5)
        #expect(effects.isEmpty)
    }

    @Test("syncCalendar leaves an existing-batch assembly alone")
    func syncCalendarDoesNotAdoptExisting() {
        var state = session()
        state.assembly = PCEventBatchAssembleUnitOfWork.existing(batch("morning", on: 1, id: 7))
        state.stage = .batchEditor

        let (next, _) = reduce(state, .syncCalendar(calendarID: 42, batches: [batch("morning", on: 1, id: 77)]))

        #expect(next.assembly?.adoptedPersistedID == nil, "an opened row is not a staged one")
    }

    @Test("resetSession returns a clean state that keeps the provider")
    func resetSession() {
        let state = editing(session(), on: 1)

        let (next, effects) = reduce(state, .resetSession)

        #expect(next.stage == .idle)
        #expect(next.assembly == nil)
        #expect(next.batches.isEmpty)
        #expect(next.calendarID == 0)
        #expect(next.dataProvider == provider)
        #expect(effects.isEmpty)
    }

    // MARK: - Main calendar

    @Test("Leaving multi-select mode also clears the selected days")
    func setMultiSelectMode() {
        let state = multiSelecting(session(), days: [day(4)])

        let off = reduce(state, .setMultiSelectMode(false)).next
        #expect(off.multiSelectMode == false)
        #expect(off.multiSelectDays.isEmpty)

        let on = reduce(state, .setMultiSelectMode(true)).next
        #expect(on.multiSelectDays == [day(4)], "turning it on does not forget the selection")
    }

    @Test("cancelMultiSelectTapped empties the selection and rebuilds the markers")
    func cancelMultiSelectTapped() {
        let state = multiSelecting(session(), days: [day(4), day(5)])
        let (next, effects) = reduce(state, .cancelMultiSelectTapped)

        #expect(next.multiSelectDays.isEmpty)
        #expect(next.dayEventColors == PCCalendarMarkerProjector.colorsByDay(from: state.batches, using: provider))
        #expect(effects.isEmpty)
    }

    // MARK: - The multi-select session (Stage 7: colour, and confirming it)

    @Test("setMultiSelectColor stores the colour without touching anything else")
    func setMultiSelectColor() {
        let state = multiSelecting(session(), days: [day(4)])
        let (next, effects) = reduce(state, .setMultiSelectColor(.option3))

        #expect(next.multiSelectColor == .option3)
        #expect(next.multiSelectDays == state.multiSelectDays, "picking a colour selects nothing")
        #expect(next.multiSelectMode)
        // Was "a colour choice is not a write", which was true while the session's days were
        // staged and nothing existed on disk. Now the batch was written when the days were
        // tapped, so recolouring it *is* a write — it repaints the days the user already
        // picked, and the marker would disagree with the row if it did not.
        #expect(effects.count == 1, "recolouring a session with days writes the batch")
    }

    @Test("Leaving multi-select clears the days *and* the colour")
    func leavingMultiSelectClearsColour() {
        var state = multiSelecting(session(), days: [day(4)])
        state.multiSelectColor = .option2

        let next = reduce(state, .setMultiSelectMode(false)).next

        #expect(!next.multiSelectMode)
        #expect(next.multiSelectDays.isEmpty)
        #expect(
            next.multiSelectColor == nil,
            "a stale colour would silently colour the next session's batch"
        )
    }

    @Test("Tapping days in a session builds one batch, updated in place")
    func multiSelectBuildsOneBatch() throws {
        var state = multiSelecting(session(), days: [day(4)], color: .option2)

        // First day: a batch is created.
        let first = reduce(state, .dayTappedInCalendar(day(6))).next
        let afterFirst = try #require(first.multiSelectAssembly)
        #expect(afterFirst.batch.events.count == 2, "both selected days are in it")

        // Second day: the *same* batch, because the assembly keeps its identity. This is the
        // bug worth naming — rebuilding it per tap gives a fresh `pendingID`, a different
        // `mergeKey`, and a second batch covering the same day.
        state = first
        let second = reduce(state, .dayTappedInCalendar(day(9))).next
        #expect(
            second.multiSelectAssembly?.batch.pendingID == afterFirst.batch.pendingID,
            "the session reuses one batch"
        )
        #expect(second.batches.count == 2, "one committed + this one, not three")
        let grown = try #require(second.multiSelectAssembly)
        #expect(grown.batch.events.count == 3, "and it grew to three days")
    }

    /// The reported symptom, end to end in the reducer: tapping 17, 18 and 19 produced three
    /// batches, the first holding three events, the second two, the third one. Cumulative,
    /// which is the signature of a batch being *rebuilt* per tap — each rebuild gets a new
    /// `pendingID`, a different `mergeKey`, and lands beside the last instead of replacing it.
    @Test("Tapping three days in a session leaves exactly one batch with three events")
    func threeTappedDaysProduceOneBatch() throws {
        var state = multiSelecting(session(batches: []), days: [], color: .option2)

        for day in [day(17), day(18), day(19)] {
            state = reduce(state, .dayTappedInCalendar(day)).next
        }

        #expect(
            state.batches.count == 1,
            "three taps, one batch — got \(state.batches.count)"
        )
        let batch = try #require(state.batches.first)
        #expect(
            batch.events.map(\.date) == [day(17), day(18), day(19)].map(provider.startOfDay(for:)),
            "holding all three days, not a growing pile"
        )
        #expect(batch.colorName == "eventColorOption2", "in the chosen colour")
    }

    /// The same three taps, with the reload that follows each one.
    ///
    /// `threeTappedDaysProduceOneBatch` above is not enough, and its passing is the reason
    /// this bug shipped. It drives the reducer alone, so the registry never comes back from
    /// the store and the session's `mergeKey` is the same `.pending(…)` on every tap — which
    /// is the only condition under which one assembly can hold. In the app it is not true:
    /// every write in a session re-fetches and broadcasts, `SingleCalendarModel` answers
    /// with `syncCalendar`, and `batches` is replaced wholesale by rows the database has
    /// given real ids. The session's own assembly was left out of the adoption that follows,
    /// so after the first tap its key answered to nothing and every tap after it appended.
    ///
    /// The signature is one batch per tap holding the days accumulated so far — which is why
    /// the report reads as "first batch has 4 events, third has 3" rather than as duplicates.
    @Test("A reload between taps does not split a session into one batch per tap")
    func reloadBetweenTapsLeavesOneBatch() throws {
        var state = multiSelecting(session(batches: []), days: [], color: .option2)

        for tapped in [day(17), day(18), day(19)] {
            state = reduce(state, .dayTappedInCalendar(tapped)).next
            // Exactly what the store does after a write: read the calendar back and hand the
            // rows over, ids and all.
            state = reduce(state, .syncCalendar(calendarID: 42, batches: reloaded(state.batches))).next
        }

        #expect(
            state.batches.count == 1,
            "three taps and three reloads, one batch — got \(state.batches.count)"
        )
        let batch = try #require(state.batches.first)
        #expect(
            batch.events.map { provider.startOfDay(for: $0.date) }
                == [day(17), day(18), day(19)].map(provider.startOfDay(for:)),
            "holding all three days, not a growing pile"
        )
        #expect(batch.persistedID != nil, "settled on the id the store gave it")
        #expect(
            state.multiSelectAssembly?.adoptedPersistedID == batch.persistedID,
            "and the session knows that id, which is what makes the next tap replace rather than append"
        )
    }

    /// The reload the session *cannot* survive on its own: a tap lands before the write it
    /// triggered has come back, so the row in the database is the batch as it was then.
    ///
    /// This is the timing that decides whether the bug shows up at all, which is why the
    /// test above can pass on one machine and fail on another. Adoption matches on content,
    /// so requiring the day sets to be equal meant a mid-flight tap left the session
    /// unadopted *permanently* — and with nothing to drop the earlier shape, that row stayed
    /// in the registry beside the new one for good, painting its days a second time.
    @Test("A tap that outruns its own write does not strand the shape the write left behind")
    func tapArrivingMidRoundTripDoesNotLeaveASnapshot() throws {
        var state = multiSelecting(session(batches: []), days: [], color: .option2)

        // Two taps, then *one* reload: the second tap beat the first write home, so the
        // database holds the one-day shape.
        state = reduce(state, .dayTappedInCalendar(day(17))).next
        state = reduce(state, .dayTappedInCalendar(day(18))).next
        state = reduce(state, .syncCalendar(calendarID: 42, batches: reloaded(state.batches))).next

        #expect(
            state.batches.count == 1,
            "the one-day snapshot is dropped, not kept beside the session — got \(state.batches.count)"
        )
        let settled = try #require(state.batches.first)
        #expect(settled.events.count == 2, "on both days")
        #expect(
            settled.persistedID == state.multiSelectAssembly?.adoptedPersistedID,
            "and the session is settled on it"
        )
        #expect(
            state.dayEventColors.values.flatMap { $0 }.count == 2,
            "two markers, not three: one per day, not one per row"
        )
    }

    /// A session's reload must not delete rows it has nothing to do with.
    ///
    /// `withoutRowsOutgrown` is scoped to a live session for this reason. It is a
    /// content-based deletion and content is a weak identity, so it is only safe while the
    /// thing doing the deleting is the session that produced the content. Applied to the
    /// batch editor it would be a batch the user is editing removing a neighbour that
    /// happens to share its name and colour.
    @Test("A session's reload leaves unrelated rows alone")
    func sessionReloadDoesNotTouchUnrelatedRows() throws {
        // Two "New event" batches in the chosen colour, one on a day the session holds and
        // one on a day it does not. The second is the row that must survive.
        var state = session(batches: [
            Fixture.batch("New event", on: 17, id: 1, color: "eventColorOption2"),
            Fixture.batch("New event", on: 21, id: 2, color: "eventColorOption2"),
        ])
        state = multiSelecting(state, days: [], color: .option2)
        state = reduce(state, .dayTappedInCalendar(day(17))).next

        state = reduce(state, .syncCalendar(calendarID: 42, batches: reloaded(state.batches))).next

        #expect(state.batches.count == 2, "the neighbour is not the session's history — got \(state.batches.count)")
        #expect(
            state.batches.contains { $0.events.contains { provider.isSameDay($0.date, day(21)) } },
            "day 21 still has its batch"
        )
    }

    /// Days must not be tappable before a colour is chosen.
    ///
    /// The first version defaulted to the first colour, which made an uncoloured session
    /// behave like a coloured one and quietly wrote batches the user never chose a colour for.
    /// Choosing the colour is the gesture that says "start a batch".
    ///
    /// **Premise changed.** This used to assert only that no *batch* appeared, which read as
    /// "no batch, but the day is selected" and was taken at face value: the days were
    /// recorded, nothing was written, and `derivedDayEventColors` — which needs a colour to
    /// paint from — showed nothing. So the session silently held four days and no batch,
    /// and the moment the user picked a colour all four appeared, already coloured, with
    /// nothing behind them. The guard sat below the `multiSelectDays` mutation, so it
    /// refused the write while accepting the selection.
    ///
    /// It now sits above it, and an uncoloured tap is inert in the strong sense: nothing
    /// about the state moves.
    @Test("A day tap before a colour is chosen leaves the state untouched")
    func dayTapBeforeAColourIsInert() {
        var state = multiSelecting(session(batches: []), days: [], color: nil)

        let (next, effects) = reduce(state, .dayTappedInCalendar(day(17)))

        #expect(next.batches.isEmpty, "no batch without a chosen colour")
        #expect(next.multiSelectAssembly == nil, "and nothing staged to become one")
        #expect(next.multiSelectDays.isEmpty, "and no day selected: the tap is not a selection yet")
        #expect(effects.isEmpty, "and nothing written")

        // A second tap must not accumulate either — the first version's failure was
        // cumulative, so one tap would not have shown it.
        state = next
        state = reduce(state, .dayTappedInCalendar(day(18))).next
        state = reduce(state, .dayTappedInCalendar(day(19))).next
        #expect(state.multiSelectDays.isEmpty, "still nothing selected")
        #expect(state.batches.isEmpty, "and still no batch")
    }

    /// Choosing a colour is what turns the days already tapped into a batch.
    ///
    /// Not reachable from the UI — the guard above means an uncoloured session has no days
    /// — so this is a state no production sequence builds. It is pinned because the two
    /// halves are separately correct and together they are the retro-paint the guard was
    /// added to stop: days present, colour arriving, and a batch that still does not.
    @Test("Choosing a colour does not conjure a batch out of nothing")
    func choosingAColourWithDaysStagedHasNoBatch() {
        var state = multiSelecting(session(batches: []), days: [], color: nil)
        // Reach past the tap guard, the only way to get here, to assert what the other half
        // does with it.
        state.multiSelectDays = [provider.startOfDay(for: day(17)), provider.startOfDay(for: day(18))]

        let next = reduce(state, .setMultiSelectColor(.option3)).next

        #expect(next.multiSelectColor == .option3)
        #expect(next.multiSelectAssembly == nil, "a colour is not a batch")
        #expect(next.batches.isEmpty, "and nothing is written for a session that has no row")
        // The markers do paint — which is exactly why the days could not be allowed to
        // accumulate without a colour in the first place.
        #expect(next.dayEventColors.values.flatMap { $0 } == ["eventColorOption3", "eventColorOption3"])
    }

    /// Toggling the last day back off has to take the row with it.
    ///
    /// A session writes on every tap and has no Back button and no Save, so `resolved()`
    /// returning `nil` for an emptied batch is a delete that only the batch editor's leaving
    /// handles anywhere else. Without a branch for it the row the user had just emptied was
    /// still the last one written, so the day stayed coloured on the calendar and stayed in
    /// the database.
    ///
    /// The session deletes *immediately* where the editor deletes on the way out, and the
    /// asymmetry is deliberate: there is no "next tap" to undo a mis-tap with, so the row has
    /// to go before the user can do anything else with it.
    @Test("Toggling every day back off removes the session's batch")
    func multiSelectTogglingTheLastDayOffDeletesTheBatch() throws {
        var state = multiSelecting(session(batches: []), days: [], color: .option2)
        state = reduce(state, .dayTappedInCalendar(day(17))).next
        #expect(state.batches.count == 1)

        // Give the session an id the way a reload would, so the removal has to find the row
        // by that key rather than by a `.pending(…)` one that matches nothing.
        state = reduce(state, .syncCalendar(calendarID: 42, batches: reloaded(state.batches))).next
        let row = try #require(state.batches.first)
        #expect(row.persistedID != nil, "the row came back with an id")

        state = reduce(state, .dayTappedInCalendar(day(17))).next

        #expect(state.multiSelectDays.isEmpty)
        #expect(state.multiSelectAssembly?.batch.isEmpty == true, "the batch is empty")
        #expect(state.batches.isEmpty, "and so is the registry — the day loses its marker")
    }

    /// Confirming an emptied session must not leave a batch behind — not in the registry, and
    /// not staged either.
    ///
    /// The staging half is the one that was broken. Toggling a day off deletes the row, so by
    /// the time Confirm ran there was nothing in `batches`, and `next.assembly = session`
    /// installed the empty shell anyway: a named, coloured batch with no events, resolving to
    /// nothing, which no write can carry and no marker can show. Nothing user-visible — which
    /// is why it survived — but it is exactly the state that should be unrepresentable.
    ///
    /// Built through `startNewBatch`-shaped taps rather than a hand-made session, so the
    /// sequence is the one a user can actually perform: enter, choose a colour, tap, tap again.
    @Test("Confirming a session whose days were all toggled back off leaves no batch at all")
    func confirmingAnEmptiedSessionLeavesNoBatch() throws {
        var state = multiSelecting(session(batches: []), days: [], color: .option2)
        state = reduce(state, .dayTappedInCalendar(day(17))).next
        #expect(state.batches.count == 1, "setup: the tap wrote the batch")

        // Give it an id the way a reload would. This is what makes the assertion below mean
        // something: the row has a *persisted* id by the time it is deleted, so the filter has
        // to find it by `assembly.mergeKey` (which prefers the adopted id) rather than by the
        // `.pending(…)` key it was created under — a `.pending` key matches no registry row.
        state = reduce(state, .syncCalendar(calendarID: 42, batches: reloaded(state.batches))).next
        #expect(state.batches.first?.persistedID != nil, "setup: the row came back with an id")
        state = reduce(state, .dayTappedInCalendar(day(17))).next
        #expect(state.batches.isEmpty, "setup: the second tap took the row away again")

        let (next, effects) = reduce(state, .confirmMultiSelectTapped)

        #expect(!next.multiSelectMode, "the session still ends — the user is not left in it")
        #expect(next.multiSelectAssembly == nil)
        #expect(next.multiSelectDays.isEmpty)
        #expect(next.multiSelectColor == nil)
        #expect(
            next.assembly == nil,
            "and no empty batch is staged in its place; got \(String(describing: next.assembly))"
        )
        #expect(next.batches.isEmpty, "the registry is still empty")
        #expect(next.stage == .idle, "and nothing is pushed")
        #expect(effects.isEmpty, "there was no row, so there is nothing to write")
        #expect(
            next.dayEventColors.isEmpty,
            "so nothing is marked — an empty batch paints nothing, but it should not be here to paint"
        )
    }

    @Test("confirmMultiSelectTapped ends the session without opening the editor")
    func confirmMultiSelectEndsTheSession() throws {
        let state = multiSelecting(session(), days: [day(6), day(4)], color: .option2)
        let (next, effects) = reduce(state, .confirmMultiSelectTapped)

        // The days were written as they were tapped, so Save has nothing to commit. It ends
        // the session and leaves the calendar in single-select. It does not open the editor:
        // that was a review step over staged data, and there is no staged data left.
        #expect(!next.multiSelectMode, "single-select after Save")
        #expect(next.multiSelectDays.isEmpty)
        #expect(next.multiSelectColor == nil)
        #expect(next.multiSelectAssembly == nil, "the scratchpad is released")
        #expect(next.stage == .idle, "no push into the batch editor")
        #expect(next.navigationRequest == nil, "Save is not a navigation")
        #expect(effects.isEmpty, "the batch was already written; there is nothing to write")
    }

    @Test("Confirming ends the session, so the calendar behind the editor is not left mid-selection")
    func confirmMultiSelectClearsTheSession() throws {
        var state = multiSelecting(session(), days: [day(4), day(5)])
        state.multiSelectColor = .option1

        let next = reduce(state, .confirmMultiSelectTapped).next

        #expect(!next.multiSelectMode)
        #expect(next.multiSelectDays.isEmpty)
        #expect(next.multiSelectColor == nil)
        #expect(next.assembly != nil, "the session became a staged batch, not a discarded one")
        #expect(
            next.dayEventColors
                == PCCalendarMarkerProjector.colorsByDay(
                    from: state.batches,
                    includingStaged: next.assembly,
                    using: provider
                ),
            "the markers have to describe the staged batch, not just the committed one"
        )
    }

    /// Save with nothing selected still ends the session — it just writes nothing.
    ///
    /// It used to be rejected outright, because it used to build a batch and open an editor
    /// for it. Now it cannot build anything, and a checkmark that does nothing when tapped is
    /// a worse affordance than one that simply closes the session.
    @Test("confirmMultiSelectTapped with nothing to save ends the session and writes nothing")
    func confirmMultiSelectIsRejected() throws {
        let committed = session()

        let uncoloured = multiSelecting(committed, days: [day(4)], color: nil)
        let afterUncoloured = reduce(uncoloured, .confirmMultiSelectTapped).next
        #expect(!afterUncoloured.multiSelectMode, "the session ended")
        #expect(afterUncoloured.batches == committed.batches, "and no batch was invented")

        var empty = multiSelecting(committed, days: [], color: .option1)
        empty.multiSelectAssembly = nil
        let afterEmpty = reduce(empty, .confirmMultiSelectTapped).next
        #expect(!afterEmpty.multiSelectMode, "the session ended")
        #expect(afterEmpty.batches == committed.batches, "and nothing was written")

        // Not in a session at all: only the mode guard can reject this, and rejecting means
        // leaving the state untouched.
        var notSelecting = committed
        notSelecting.multiSelectDays = [day(4)]
        notSelecting.multiSelectColor = .option1
        #expect(
            reduce(notSelecting, .confirmMultiSelectTapped).next == notSelecting,
            "outside a session, Save is inert"
        )
    }

    @Test("setNumberOfColumns writes, and does so only when the count really changes")
    func setNumberOfColumns() {
        let state = session()
        let (next, effects) = reduce(state, .setNumberOfColumns(5))

        #expect(next.numberOfColumns == 5)
        #expect(effects == [.writeCalendar(calendarID: 42, numberOfColumns: 5, batches: state.batches)])
        #expect(reduce(state, .setNumberOfColumns(3)).effects.isEmpty, "already 3")
    }

    @Test("setEditorYear and setScrollAnchor are view state and never write")
    func setEditorViewState() {
        let state = session()
        #expect(reduce(state, .setEditorYear(2027)).next.editorYear == 2027)
        #expect(reduce(state, .setEditorYear(2027)).effects.isEmpty)
        #expect(reduce(state, .setScrollAnchor(day(6))).next.scrollAnchor == day(6))
        #expect(reduce(state, .setScrollAnchor(day(6))).effects.isEmpty)
    }

    // MARK: - Cross-cutting

    /// Every action must be reachable from a test, so a newly added case cannot ship
    /// unhandled.
    ///
    /// Listed as state/action *pairs* rather than one action list over a shared set of
    /// states, because three of them carry an identity payload that only matches a
    /// particular state: `openBatch` is looked up by `mergeKey` and `openEvent` by
    /// `pendingID`, so a fixed random id would simply miss and the action would look
    /// unhandled when it is in fact merely pointed at nothing.
    @Test("Every action is covered: it either changes state or emits an effect")
    func everyActionIsCovered() {
        let idle = session()
        let editing = editing(idle, on: 1)
        let staged = stagedSession()
        let multi = multiSelecting(idle, days: [day(4)])
        // `confirmMultiSelectTapped` needs a colour to build with, so the session it runs
        // against is a *coloured* one — confirming an uncoloured session is rejected and
        // covered separately.
        var multiColoured = multi
        multiColoured.multiSelectColor = .option3

        let openable = idle
        let openableKey = try! #require(openable.batches.first?.mergeKey)
        let openableEvent = editing.assembly.map { try! #require($0.batch.events.first?.pendingID) } ?? UUID()

        let cases: [(name: String, state: PCEventSelectionState, action: PCEventSelectionAction)] = [
            ("ensureAssemblyStarted", editing, .ensureAssemblyStarted),
            ("dayTappedInCalendar", idle, .dayTappedInCalendar(day(4))),
            ("startNewBatch", idle, .startNewBatch(on: day(4))),
            ("openBatch", openable, .openBatch(id: openableKey)),
            ("backTapped", staged, .backTapped),
            ("closeTapped", editing, .closeTapped),
            ("cancelTapped", editing, .cancelTapped),
            ("navigationRequestHandled", editing, .navigationRequestHandled),
            ("setBatchName", editing, .setBatchName("n")),
            ("setBatchColor", editing, .setBatchColor(.option1)),
            ("toggleDay", editing, .toggleDay(day(5))),
            ("removeEvent", editing, .removeEvent(pendingID: try! #require(editing.assembly?.batch.events.first?.pendingID))),
            ("openEvent", editing, .openEvent(pendingID: openableEvent)),
            ("setEventName", staged, .setEventName("n")),
            ("setEventDate", staged, .setEventDate(day(7))),
            ("setEventColor", staged, .setEventColor(.option1)),
            ("discardEventTapped", staged, .discardEventTapped),
            ("deleteBatches", idle, .deleteBatches(idle.batches)),
            ("setMultiSelectMode", idle, .setMultiSelectMode(true)),
            ("setMultiSelectColor", idle, .setMultiSelectColor(.option2)),
            ("confirmMultiSelectTapped", multiColoured, .confirmMultiSelectTapped),
            ("cancelMultiSelectTapped", multi, .cancelMultiSelectTapped),
            ("setNumberOfColumns", idle, .setNumberOfColumns(4)),
            ("setEditorYear", idle, .setEditorYear(2027)),
            ("setScrollAnchor", idle, .setScrollAnchor(day(6))),
            ("syncCalendar", idle, .syncCalendar(calendarID: 42, batches: [batch("x", on: 1, id: 1)])),
            ("resetSession", editing, .resetSession)
        ]

        // Two actions are *supposed* to change nothing, so the rule cannot be "every
        // action must do something" — it is "every action is either exercised or
        // deliberately inert". `ensureAssemblyStarted` is a no-op by design, and
        // `navigationRequestHandled` on a state with no pending request has nothing to
        // clear. Both are asserted inert in their own tests.
        let inertByDesign: Set<String> = ["ensureAssemblyStarted", "navigationRequestHandled"]

        let uncovered = cases.filter { _, state, action in
            let next = pcEventSelectionReducer(state, action)
            return next == state && pcEventSelectionEffects(action, state, next).isEmpty
        }.map(\.name)

        #expect(
            Set(uncovered).subtracting(inertByDesign).isEmpty,
            "these actions are not inert by design and nothing exercised them: \(uncovered)"
        )
        #expect(
            Set(cases.map(\.name)).isSuperset(of: inertByDesign),
            "the inert set names actions that are not in the case list"
        )
        // `Comment(rawValue:)` rather than a bare `String`: a literal `String` in a trailing
        // position is read as a comment *expression*, and only a `String` literal converts.
        let message = Comment(rawValue: """
            the §6.2 case list, less the three that went with the checkmarks: `saveTapped`, \
            `saveEventTapped` and `commitTapped`. None of them had a button by the time this \
            ran — `commitTapped` never did — and an action no screen can send is a case nothing \
            can exercise.
            """)
        #expect(cases.count == 27, message)
    }

    @Test("A rejected action leaves the state byte-identical")
    func rejectedActionsAreInert() {
        let state = session()

        // The two the plan names explicitly.
        #expect(reduce(state, .setBatchName("n")).next == state, "no assembly")
        #expect(reduce(state, .openEvent(pendingID: UUID())).next == state, "unknown event")

        // And the rest of the guarded ones.
        #expect(reduce(state, .setBatchColor(.option1)).next == state)
        #expect(reduce(state, .removeEvent(pendingID: UUID())).next == state)
        #expect(reduce(state, .toggleDay(day(5))).next == state)
        #expect(reduce(state, .setEventName("n")).next == state)
        #expect(reduce(state, .setEventDate(day(5))).next == state)
        #expect(reduce(state, .setEventColor(.option1)).next == state)
        #expect(reduce(state, .backTapped).next == state)
        #expect(reduce(state, .openBatch(id: .pending(UUID()))).next == state)
    }

    @Test("A rejected action emits no navigation and no effect")
    func rejectedActionsAreSilent() {
        let state = session()

        for (name, action) in allActions {
            let next = pcEventSelectionReducer(state, action)
            guard next == state else { continue }  // not rejected, so out of scope
            #expect(next.navigationRequest == state.navigationRequest, "\(name) navigated while rejected")
            #expect(pcEventSelectionEffects(action, state, next).isEmpty, "\(name) emitted while rejected")
        }
    }

    @Test("The reducer is a function of its inputs: same inputs, same outputs")
    func reducerIsPure() {
        let state = editing(session(), on: 1)

        for (name, action) in allActions {
            #expect(
                normalized(pcEventSelectionReducer(state, action))
                    == normalized(pcEventSelectionReducer(state, action)),
                "\(name) is not deterministic, ignoring the ids it mints"
            )
        }
    }

    @Test("No action reuses the id of a navigation request already pending")
    func navigationIdsAreFresh() {
        let state = session()
        var withPending = state
        withPending.navigationRequest = NavigationRequest(id: 4, target: .pop)

        for (name, action) in allActions {
            let next = pcEventSelectionReducer(state, action)
            guard let request = next.navigationRequest else { continue }
            #expect(request.id == 1, "\(name)")

            let chained = pcEventSelectionReducer(withPending, action)
            guard let chainedRequest = chained.navigationRequest else { continue }
            #expect(chainedRequest.id == 5, "\(name) did not advance past a pending request")
        }
    }

    // MARK: - Action inventory

    /// The §6.2 case list, less the three that went with the checkmarks. These walks run
    /// against a plain session, so the multi-select cases are exercised in their *rejected*
    /// form here; the accepted form is covered by `everyActionIsCovered` and the dedicated
    /// multi-select tests.
    private var allActions: [(name: String, action: PCEventSelectionAction)] {
        [
            ("ensureAssemblyStarted", .ensureAssemblyStarted),
            ("dayTappedInCalendar", .dayTappedInCalendar(day(4))),
            ("startNewBatch", .startNewBatch(on: day(4))),
            ("openBatch", .openBatch(id: .pending(UUID()))),
            ("backTapped", .backTapped),
            ("closeTapped", .closeTapped),
            ("cancelTapped", .cancelTapped),
            ("navigationRequestHandled", .navigationRequestHandled),
            ("setBatchName", .setBatchName("n")),
            ("setBatchColor", .setBatchColor(.option1)),
            ("toggleDay", .toggleDay(day(5))),
            ("removeEvent", .removeEvent(pendingID: UUID())),
            ("openEvent", .openEvent(pendingID: UUID())),
            ("setEventName", .setEventName("n")),
            ("setEventDate", .setEventDate(day(7))),
            ("setEventColor", .setEventColor(.option1)),
            ("discardEventTapped", .discardEventTapped),
            ("deleteBatches", .deleteBatches([])),
            ("setMultiSelectMode", .setMultiSelectMode(true)),
            ("setMultiSelectColor", .setMultiSelectColor(.option1)),
            ("confirmMultiSelectTapped", .confirmMultiSelectTapped),
            ("cancelMultiSelectTapped", .cancelMultiSelectTapped),
            ("setNumberOfColumns", .setNumberOfColumns(4)),
            ("setEditorYear", .setEditorYear(2027)),
            ("setScrollAnchor", .setScrollAnchor(day(6))),
            ("syncCalendar", .syncCalendar(calendarID: 42, batches: [batch("x", on: 1, id: 1)])),
            ("resetSession", .resetSession)
        ]
    }

    /// A staged, unsaved assembly whose content a write would reproduce exactly.
    private func stagedBatch() -> PCEventBatchAssembleUnitOfWork {
        PCEventBatchAssembleUnitOfWork
            .new(anchor: day(2), colorName: "", using: provider)
            .renaming("morning")
            .recoloring(.option1)
    }
}
