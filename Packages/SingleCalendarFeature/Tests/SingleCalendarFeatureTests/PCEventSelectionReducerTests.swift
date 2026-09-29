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

    private func normalized(_ assembler: BatchAssembler) -> BatchAssembler {
        // Via the public factory: `init(batch:origin:)` is private by design. The origin
        // is normalised too, since it carries a minted UUID in the `.existing` case.
        BatchAssembler
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
        state.dayEventColors = PCCalendarMarkerProjector.colorsByDay(from: state.batches, using: provider)
        return state
    }

    /// A named, coloured assembly on the given day — past `canSave`.
    private func editing(_ state: PCEventSelectionState, on dayOfMonth: Int) -> PCEventSelectionState {
        var next = state
        next.day = day(dayOfMonth)
        next.assembly = BatchAssembler
            .new(anchor: day(dayOfMonth), colorName: "", using: provider)
            .renaming("edited")
            .recoloring(.option2)
        next.stage = .batchEditor
        return next
    }

    private func showingDayList(_ state: PCEventSelectionState, on d: Date) -> PCEventSelectionState {
        var next = state
        next.day = d
        next.stage = .dayList(day: d)
        return next
    }

    private func multiSelecting(_ state: PCEventSelectionState, days: [Date]) -> PCEventSelectionState {
        var next = state
        next.multiSelectMode = true
        next.multiSelectDays = days
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
        #expect(next.isDirty)
        #expect(next.canSave == false, "a merely-tapped day has no name and no colour yet")
        #expect(next.navigationRequest?.target == .pushBatchEditor)
        #expect(effects.isEmpty, "staging is not a write")
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
        #expect(next.isDirty)
        #expect(next.navigationRequest?.target == .pushBatchEditor)
        #expect(effects.isEmpty)
    }

    @Test("openBatch stages the batch it found and asks for a push")
    func openBatch() {
        // The session has to hold the very row being opened: `openBatch` looks it up by
        // `pendingID`, and a second call to `batch(...)` would mint a different UUID.
        let target = batch("morning", on: 1, id: 7)
        let (next, _) = reduce(session(batches: [target]), .openBatch(pendingID: target.pendingID))

        #expect(next.stage == .batchEditor)
        #expect(next.assembly?.batch.pendingID == target.pendingID)
        #expect(next.day == target.date)
        #expect(next.scrollAnchor == target.date)
        #expect(next.isDirty)
        #expect(next.navigationRequest?.target == .pushBatchEditor)
    }

    @Test("openBatch with an unknown id is rejected")
    func openBatchUnknown() {
        let state = session()
        #expect(reduce(state, .openBatch(pendingID: UUID())).next == state)
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

    @Test("Back from the batch editor discards the staged edit and returns to the day list")
    func backFromBatchEditor() {
        let (next, _) = reduce(editing(session(), on: 1), .backTapped)

        #expect(next.assembly == nil, "back discards; save is what commits")
        #expect(next.stage == .dayList(day: day(1)))
        #expect(next.navigationRequest?.target == .pop)
    }

    @Test("Back from the batch editor with no day falls back to idle")
    func backFromBatchEditorNoDay() {
        var state = session()
        state.assembly = BatchAssembler.new(anchor: day(3), colorName: "", using: provider)
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
        #expect(next.isDirty == false)
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
        #expect(next.isDirty)
        #expect(effects.isEmpty)
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
        #expect(next.isDirty)
        #expect(effects.isEmpty)
    }

    @Test("toggleDay adds a day to the assembly and to the markers")
    func toggleDay() {
        let (next, effects) = reduce(editing(session(), on: 1), .toggleDay(day(5)))

        #expect(next.assembly?.batch.events.count == 2)
        #expect(next.dayEventColors[provider.startOfDay(for: day(5))] != nil)
        #expect(next.isDirty)
        #expect(effects.isEmpty)
    }

    @Test("toggleDay is refused outside the batch editor")
    func toggleDayWrongStage() {
        var state = session()
        state.assembly = BatchAssembler.new(anchor: day(1), colorName: "", using: provider)
        state.stage = .dayList(day: day(1))

        #expect(reduce(state, .toggleDay(day(5))).next == state)
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
        #expect(next.isDirty)
        #expect(effects.isEmpty)
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
        #expect(colored.isDirty)
        let assembly = try! #require(base.assembly)
        let stagedEvent = try! #require(assembly.batch.events.first)
        #expect(
            stagedEvent.name.isEmpty,
            "the staged placeholder is untouched until the event is saved"
        )
    }

    @Test("Event edits without a draft are rejected")
    func editEventDraftWithoutDraft() {
        let state = editing(session(), on: 1)
        #expect(reduce(state, .setEventName("n")).next == state)
        #expect(reduce(state, .setEventDate(day(8))).next == state)
        #expect(reduce(state, .setEventColor(.option1)).next == state)
    }

    @Test("saveEventTapped applies the draft and pops, without writing")
    func saveEventTapped() {
        let base = editing(session(), on: 1)
        let event = try! #require(base.assembly?.batch.events.first)
        var state = reduce(base, .openEvent(pendingID: event.pendingID)).next
        state = reduce(state, .setEventName("Edited")).next

        let (next, effects) = reduce(state, .saveEventTapped)

        #expect(try! #require(next.assembly).batch.events.contains(where: { $0.name == "Edited" }))
        #expect(next.eventDraft == nil)
        #expect(next.stage == .batchEditor)
        #expect(next.isDirty)
        #expect(next.navigationRequest?.target == .pop)
        #expect(effects.isEmpty, "an event save does not commit the batch")
    }

    @Test("saveEventTapped with an unnamed draft is rejected and leaves the editor open")
    func saveEventTappedUnnamed() {
        let base = editing(session(), on: 1)
        let event = try! #require(base.assembly?.batch.events.first)
        // A placeholder event has an empty name, so this is the everyday case of opening
        // a day and saving without typing anything.
        let opened = reduce(base, .openEvent(pendingID: event.pendingID)).next

        #expect(reduce(opened, .saveEventTapped).next == opened,
                "rejected: the draft survives and the editor stays open")
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
        #expect(kept.name.isEmpty, "the edit is gone: the batch still holds the unnamed placeholder")
        #expect(next.navigationRequest?.target == .pop)
        #expect(effects.isEmpty)
    }

    // MARK: - Persistence

    @Test("commitTapped merges the assembly into the registry and writes once")
    func commitTapped() {
        let state = editing(session(), on: 1)
        let pendingID = try! #require(state.assembly?.batch.pendingID)
        let (next, effects) = reduce(state, .commitTapped)

        #expect(next.batches.contains { $0.pendingID == pendingID })
        #expect(next.batches.count == 2, "the committed row for that day was replaced, not duplicated")
        #expect(next.isDirty)
        #expect(effects == [.writeCalendar(calendarID: 42, numberOfColumns: 3, batches: next.batches)])
    }

    @Test("commitTapped with an unsavable assembly is rejected and writes nothing")
    func commitTappedUnsaveable() {
        var state = session()
        state.assembly = BatchAssembler.new(anchor: day(1), colorName: "", using: provider)
        state.stage = .batchEditor

        let (next, effects) = reduce(state, .commitTapped)

        #expect(next == state)
        #expect(effects.isEmpty)
    }

    @Test("saveTapped from the day list just unwinds to the root")
    func saveTappedFromDayList() {
        let state = showingDayList(session(), on: day(1))
        let (next, effects) = reduce(state, .saveTapped)

        #expect(next.stage == .idle)
        #expect(next.day == nil)
        #expect(next.navigationRequest?.target == .popToCalendarRoot)
        #expect(
            effects == [.writeCalendar(calendarID: 42, numberOfColumns: 3, batches: state.batches)],
            "a successful save writes, even though it moved no batches"
        )
    }

    @Test("saveTapped from the batch editor commits, clears the dirty flag and pops")
    func saveTappedFromBatchEditor() {
        let (next, effects) = reduce(editing(session(), on: 1), .saveTapped)

        #expect(next.assembly == nil)
        #expect(next.stage == .dayList(day: day(1)))
        #expect(next.didSave)
        #expect(next.isDirty == false)
        #expect(next.batches.contains { $0.name == "edited" })
        #expect(next.navigationRequest?.target == .pop)
        #expect(effects == [.writeCalendar(calendarID: 42, numberOfColumns: 3, batches: next.batches)])
    }

    @Test("saveTapped on an emptied assembly removes the row and unwinds to the root")
    func saveTappedEmptied() {
        let state = editing(session(), on: 1)
        let pendingID = try! #require(state.assembly?.batch.events.first?.pendingID)
        let emptied = reduce(state, .removeEvent(pendingID: pendingID)).next

        let (next, effects) = reduce(emptied, .saveTapped)

        #expect(next.assembly == nil)
        #expect(next.stage == .idle)
        #expect(next.didSave)
        #expect(next.batches.count == 1, "the emptied row left the registry")
        #expect(effects == [.writeCalendar(calendarID: 42, numberOfColumns: 3, batches: next.batches)])
    }

    @Test("saveTapped on an unsavable but non-empty assembly is rejected")
    func saveTappedUnsaveable() {
        var state = session()
        state.assembly = BatchAssembler.new(anchor: day(3), colorName: "", using: provider)
        state.stage = .batchEditor
        state.day = day(3)

        let (next, effects) = reduce(state, .saveTapped)

        #expect(next == state, "a nameless, colourless batch is neither saved nor removed")
        #expect(effects.isEmpty)
    }

    @Test("saveTapped from the event editor applies the draft, commits and pops")
    func saveTappedFromEventEditor() {
        let base = editing(session(), on: 1)
        let event = try! #require(base.assembly?.batch.events.first)
        var state = reduce(base, .openEvent(pendingID: event.pendingID)).next
        state = reduce(state, .setEventName("Composed")).next

        let (next, effects) = reduce(state, .saveTapped)

        #expect(next.batches.contains { row in row.events.contains { $0.name == "Composed" } })
        #expect(next.eventDraft == nil)
        #expect(next.assembly == nil)
        #expect(next.stage == .dayList(day: day(1)))
        #expect(next.didSave)
        #expect(next.isDirty == false)
        #expect(next.navigationRequest?.target == .pop)
        #expect(effects == [.writeCalendar(calendarID: 42, numberOfColumns: 3, batches: next.batches)])
    }

    @Test("deleteBatches removes the rows, writes, and unwinds when the day empties")
    func deleteBatches() {
        let state = showingDayList(session(), on: day(1))
        let (next, effects) = reduce(state, .deleteBatches(state.batches))

        #expect(next.batches.isEmpty)
        #expect(next.isDirty)
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
        #expect(next.isDirty == false)
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
        // event — including the event's *empty* name, because that is what was persisted —
        // but now with a real id and a fresh pendingID, since a DTO carries none.
        let incoming = [batch("morning", on: 2, id: 77, eventName: "")]

        let (next, effects) = reduce(state, .syncCalendar(calendarID: 42, batches: incoming))

        #expect(next.assembly?.adoptedPersistedID == 77, "so the next commit updates row 77")
        #expect(next.assembly?.resolved()?.persistedID == 77)
        #expect(
            effects == [.writeCalendar(calendarID: 42, numberOfColumns: 3, batches: incoming)],
            "the reassignment has to land, so this sync does write"
        )
    }

    @Test("syncCalendar does not re-adopt an assembly that already has an id")
    func syncCalendarAdoptsOnce() {
        var state = session(batches: [])
        state.assembly = stagedBatch().adopting(persistedID: 5)
        state.stage = .batchEditor

        let (next, effects) = reduce(
            state,
            .syncCalendar(calendarID: 42, batches: [batch("morning", on: 2, id: 77, eventName: "")])
        )

        #expect(next.assembly?.adoptedPersistedID == 5)
        #expect(effects.isEmpty)
    }

    @Test("syncCalendar leaves an existing-batch assembly alone")
    func syncCalendarDoesNotAdoptExisting() {
        var state = session()
        state.assembly = BatchAssembler.existing(batch("morning", on: 1, id: 7))
        state.stage = .batchEditor

        let (next, _) = reduce(state, .syncCalendar(calendarID: 42, batches: [batch("morning", on: 1, id: 77)]))

        #expect(next.assembly?.adoptedPersistedID == nil, "an opened row is not a staged one")
    }

    @Test("resetSession returns a clean state that keeps the provider")
    func resetSession() {
        var state = editing(session(), on: 1)
        state.isDirty = true

        let (next, effects) = reduce(state, .resetSession)

        #expect(next.stage == .idle)
        #expect(next.assembly == nil)
        #expect(next.batches.isEmpty)
        #expect(next.calendarID == 0)
        #expect(next.isDirty == false)
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
        #expect(effects.isEmpty, "a colour choice is not a write")
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

    @Test("confirmMultiSelectTapped builds one batch spanning every selected day")
    func confirmMultiSelectBuildsTheBatch() throws {
        var state = multiSelecting(session(), days: [day(6), day(4)])
        state.multiSelectColor = .option2
        let (next, effects) = reduce(state, .confirmMultiSelectTapped)

        let assembly = try #require(next.assembly)
        #expect(assembly.batch.colorName == "eventColorOption2", "the session's colour is the batch's colour")
        #expect(
            assembly.batch.events.map(\.date) == [day(4), day(6)].map(provider.startOfDay(for:)),
            "one placeholder per selected day, in date order and normalised"
        )
        #expect(next.stage == .batchEditor)
        #expect(next.navigationRequest?.target == .pushBatchEditor)
        #expect(next.day == day(4), "the anchor is the earliest selected day")
        #expect(next.scrollAnchor == day(4))
        #expect(next.isDirty)
        #expect(effects.isEmpty, "confirming stages the batch; the editor's save writes it")
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

    @Test("confirmMultiSelectTapped is rejected without a colour, without days, and outside the session")
    func confirmMultiSelectIsRejected() throws {
        let committed = session()

        let uncoloured = multiSelecting(committed, days: [day(4)])
        #expect(reduce(uncoloured, .confirmMultiSelectTapped).next == uncoloured, "no colour, no batch")

        var colouless = multiSelecting(committed, days: [])
        colouless.multiSelectColor = .option1
        #expect(reduce(colouless, .confirmMultiSelectTapped).next == colouless, "no days, nothing to confirm")

        // Days and colour but *not* in a session: only the mode guard can reject this, so
        // it is the case that pins that guard down.
        var notSelecting = committed
        notSelecting.multiSelectDays = [day(4)]
        notSelecting.multiSelectColor = .option1
        #expect(
            reduce(notSelecting, .confirmMultiSelectTapped).next == notSelecting,
            "the toolbar only offers this in a session"
        )
    }

    @Test("setNumberOfColumns writes, and does so only when the count really changes")
    func setNumberOfColumns() {
        let state = session()
        let (next, effects) = reduce(state, .setNumberOfColumns(5))

        #expect(next.numberOfColumns == 5)
        #expect(next.isDirty)
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
    /// states, because three of them carry a `UUID` payload that only matches a
    /// particular state: `openBatch` and `openEvent` are looked up by `pendingID`, so a
    /// fixed random id would simply miss and the action would look unhandled when it is
    /// in fact merely pointed at nothing.
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
        let openablePendingID = try! #require(openable.batches.first?.pendingID)
        let openableEvent = editing.assembly.map { try! #require($0.batch.events.first?.pendingID) } ?? UUID()

        let cases: [(name: String, state: PCEventSelectionState, action: PCEventSelectionAction)] = [
            ("ensureAssemblyStarted", editing, .ensureAssemblyStarted),
            ("dayTappedInCalendar", idle, .dayTappedInCalendar(day(4))),
            ("startNewBatch", idle, .startNewBatch(on: day(4))),
            ("openBatch", openable, .openBatch(pendingID: openablePendingID)),
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
            ("commitTapped", editing, .commitTapped),
            ("saveTapped", editing, .saveTapped),
            ("saveEventTapped", staged, .saveEventTapped),
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
        #expect(cases.count == 30, "the 30 cases of §6.2, now that Stage 7's two have landed")
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
        #expect(reduce(state, .saveEventTapped).next == state)
        #expect(reduce(state, .commitTapped).next == state)
        #expect(reduce(state, .saveTapped).next == state)
        #expect(reduce(state, .backTapped).next == state)
        #expect(reduce(state, .openBatch(pendingID: UUID())).next == state)
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

    /// All 30 cases in §6.2. These walks run against a plain session, so the multi-select
    /// cases are exercised in their *rejected* form here; the accepted form is covered by
    /// `everyActionIsCovered` and the dedicated multi-select tests.
    private var allActions: [(name: String, action: PCEventSelectionAction)] {
        [
            ("ensureAssemblyStarted", .ensureAssemblyStarted),
            ("dayTappedInCalendar", .dayTappedInCalendar(day(4))),
            ("startNewBatch", .startNewBatch(on: day(4))),
            ("openBatch", .openBatch(pendingID: UUID())),
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
            ("commitTapped", .commitTapped),
            ("saveTapped", .saveTapped),
            ("saveEventTapped", .saveEventTapped),
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
    private func stagedBatch() -> BatchAssembler {
        BatchAssembler
            .new(anchor: day(2), colorName: "", using: provider)
            .renaming("morning")
            .recoloring(.option1)
    }
}
