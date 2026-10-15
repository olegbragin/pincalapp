//
//  PCEventSelectionTimeTests.swift
//  SingleCalendarFeatureTests
//
//  Selecting events inside the batch editor, and applying one time of day to the whole
//  selection. Its own suite rather than more cases in `PCEventSelectionReducerTests` because
//  it is one feature with its own premises: the selection is scoped to an assembly, a pick
//  writes through, and a time is *optional* — which together are what these tests check, and
//  none of which is true of the rest of the action surface.
//

import Foundation
import Testing
import CoreDomain
import DSKit
@testable import SingleCalendarFeature

@MainActor
@Suite("PCEventSelection event-time Tests")
struct PCEventSelectionTimeTests {
    private let provider = PCCalendarDataProvider()

    /// Midday UTC, so a day is named unambiguously in any zone these run in.
    private let gregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Midnight and midday in the provider's own zone, so the assertions read as the local
    /// clock the user picked rather than as UTC offsets shifted by wherever they are.
    private let localGregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    private func day(_ dayOfMonth: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = dayOfMonth
        components.hour = 12
        return gregorian.date(from: components)!
    }

    /// An instant built from the provider's own zone, so "late in the day" cannot quietly
    /// become "the next day" — the trap a UTC-pinned fixture falls into east of UTC+2.
    private func clock(_ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return localGregorian.date(from: components)!
    }

    private func hourAndMinute(_ date: Date) -> (Int, Int) {
        let components = provider.dateComponents(forDate: date)
        return (components.hour ?? -1, components.minute ?? -1)
    }

    // MARK: Fixtures

    /// A batch editor holding `days`, each event at midnight.
    ///
    /// Built by the same two steps the reducer uses — `new(anchor:)` then `toggling` per day
    /// — so the assembly's `pendingID`s are the ones the reducer would have produced. A
    /// hand-built fixture that minted its own would still be a state the reducer can act on,
    /// but not one it could have emitted, which is the fixture bug these tests would then be
    /// measuring instead of the feature.
    private func editing(days: [Int]) -> PCEventSelectionState {
        var assembly = PCEventBatchAssembleUnitOfWork
            .new(anchor: day(days[0]), colorName: PCColorOption.firstAvailable.colorName, using: provider)
        for dayOfMonth in days.dropFirst() {
            assembly = assembly.toggling(day: day(dayOfMonth), using: provider)
        }
        var state = PCEventSelectionState(dataProvider: provider)
        state.calendarID = 42
        state.day = day(days[0])
        state.assembly = assembly
        state.stage = .batchEditor
        state.batches = [assembly.resolved()!]
        state.dayEventColors = state.derivedDayEventColors
        return state
    }

    private func reduce(
        _ state: PCEventSelectionState,
        _ action: PCEventSelectionAction
    ) -> (next: PCEventSelectionState, effects: [PCEventSelectionEffect]) {
        let next = pcEventSelectionReducer(state, action)
        return (next, pcEventSelectionEffects(action, state, next))
    }

    private func ids(_ state: PCEventSelectionState) -> Set<UUID> {
        Set(state.assembly?.batch.events.map(\.pendingID) ?? [])
    }

    private func orderedIDs(_ state: PCEventSelectionState) -> [UUID] {
        state.assembly?.batch.events.map(\.pendingID) ?? []
    }

    private func selecting(
        _ state: PCEventSelectionState,
        first: Int = 0,
        count: Int = 2
    ) -> PCEventSelectionState {
        var next = state
        for id in orderedIDs(state)[first..<first + count] {
            next = pcEventSelectionReducer(next, .toggleEventSelection(pendingID: id))
        }
        return next
    }

    // MARK: Selection

    @Test("Toggling a row selects it, and only it")
    func toggleSelectsOne() {
        let state = editing(days: [1, 2, 3])
        let first = orderedIDs(state)[0]

        let (next, effects) = reduce(state, .toggleEventSelection(pendingID: first))

        #expect(next.selectedEventIDs == [first])
        #expect(next.isSelectingEvents)
        #expect(next.selectedEvents.map(\.pendingID) == [first])
        #expect(effects.isEmpty, "selecting changes what a write would act on, not the row")
    }

    @Test("Toggling the same row again deselects it")
    func toggleIsItsOwnInverse() {
        let state = editing(days: [1, 2, 3])
        let first = orderedIDs(state)[0]

        let once = pcEventSelectionReducer(state, .toggleEventSelection(pendingID: first))
        let twice = pcEventSelectionReducer(once, .toggleEventSelection(pendingID: first))

        #expect(twice.selectedEventIDs.isEmpty)
        #expect(twice.isSelectingEvents, "the mode survives an empty selection — the user is still choosing")
    }

    @Test("Selecting is inert outside the batch editor")
    func selectionIsScopedToTheEditor() {
        var state = editing(days: [1, 2])
        state.stage = .dayList(day: day(1))
        state.dayEventColors = state.derivedDayEventColors

        let (next, effects) = reduce(state, .selectAllEvents)

        #expect(next == state, "a selection is scoped to an assembly that is not on screen")
        #expect(effects.isEmpty)
    }

    @Test("Leaving the editor drops the selection")
    func selectionDoesNotOutliveTheEditor() {
        let state = selecting(editing(days: [1, 2, 3]))

        let (next, _) = reduce(state, .backTapped)

        #expect(next.selectedEventIDs.isEmpty)
        #expect(!next.isSelectingEvents)
        #expect(
            next.selectedEvents.isEmpty,
            "the stores are cached per calendar, so a selection outliving its batch would be waiting on the next one"
        )
    }

    @Test("Opening a batch drops the selection the previous one had")
    func selectionDoesNotOutliveTheBatch() {
        let state = selecting(editing(days: [1, 2, 3]))
        let target = CalendarEventBatch(
            persistedID: 7,
            name: "morning",
            colorName: "eventColorOption1",
            events: [CalendarEvent(name: "Event", date: day(9), colorName: "eventColorOption1")]
        )
        var carrying = state
        carrying.batches = [target]
        carrying.dayEventColors = carrying.derivedDayEventColors

        let (next, _) = reduce(carrying, .openBatch(id: target.mergeKey))

        #expect(next.selectedEventIDs.isEmpty)
    }

    @Test("Removing a selected event drops just that one from the selection")
    func removalPrunesItsOwnIDOnly() {
        let state = selecting(editing(days: [1, 2, 3]))
        let doomed = orderedIDs(state)[1]
        let kept = orderedIDs(state)[0]

        let (next, _) = reduce(state, .removeEvent(pendingID: doomed))

        #expect(next.selectedEventIDs == [kept])
        #expect(
            next.selectedEvents.count == next.selectedEventIDs.count,
            "a pruned selection must still resolve to events that exist"
        )
    }

    @Test("Opening an event clears the selection it was chosen from")
    func openingAnEventClearsSelection() throws {
        let state = selecting(editing(days: [1, 2, 3]))
        let target = orderedIDs(state)[0]

        let (next, _) = reduce(state, .openEvent(pendingID: target))

        #expect(next.selectedEventIDs.isEmpty)
        #expect(try next.stage == .eventEditor(batchPendingID: #require(state.assembly?.batch.pendingID), eventPendingID: target))
    }

    @Test("Select All and Clear are each other's inverse")
    func selectAllAndClear() {
        let state = editing(days: [1, 2, 3])

        let all = pcEventSelectionReducer(state, .selectAllEvents)
        #expect(all.selectedEventIDs == ids(state))

        let cleared = pcEventSelectionReducer(all, .clearEventSelection)
        #expect(cleared.selectedEventIDs.isEmpty)
        #expect(!cleared.isSelectingEvents, "Clear also leaves selection mode — the gesture is finished")
    }

    // MARK: Applying a time

    @Test("A picked time reaches every selected event and no other")
    func timeAppliesToTheSelection() throws {
        let state = selecting(editing(days: [1, 2, 3, 4]), first: 1, count: 2)
        let selected = state.selectedEventIDs
        let untouched = Set(orderedIDs(state)).subtracting(selected)

        let (next, effects) = reduce(state, .applyTimeToSelectedEvents(clock(14, 30)))

        for event in try #require(next.assembly?.batch.events) {
            if selected.contains(event.pendingID) {
                #expect(hourAndMinute(event.date) == (14, 30), "a selected event takes the pick")
                #expect(dayOf(event) == dayOf(previous: state, event: event), "and keeps its day")
            } else {
                #expect(
                    hourAndMinute(event.date) == (0, 0),
                    "an unselected event keeps the time it had — midnight, the unset"
                )
                #expect(dayOf(event) == dayOf(previous: state, event: event))
            }
        }
        #expect(untouched.count == 2)
        #expect(effects.count == 1, "four events, one selection, one write")
    }

    @Test("The day is the event's own; only the clock moves")
    func theDayIsNotThePickers() throws {
        let state = selecting(editing(days: [1, 20]), first: 0, count: 2)

        let next = reduce(state, .applyTimeToSelectedEvents(clock(9, 15))).next

        #expect(next.assembly?.batch.events.map { provider.dateComponents(forDate: $0.date).day } == [1, 20])
        for event in try #require(next.assembly?.batch.events) {
            #expect(hourAndMinute(event.date) == (9, 15))
        }
    }

    @Test("A pick with nothing selected is declined, not applied to the whole batch")
    func emptySelectionIsDeclined() {
        let state = editing(days: [1, 2, 3])
        #expect(state.selectedEventIDs.isEmpty)

        let (next, effects) = reduce(state, .applyTimeToSelectedEvents(clock(8)))

        #expect(next == state)
        #expect(effects.isEmpty, "'apply to everything' is a different gesture, and a picker must never mean it by default")
    }

    @Test("A pick preserves the events' identity, names and colours")
    func identityIsUntouched() throws {
        let state = selecting(editing(days: [1, 2]))
        let before = try #require(state.assembly?.batch)

        let next = reduce(state, .applyTimeToSelectedEvents(clock(11))).next
        let after = try #require(next.assembly?.batch)

        #expect(after.pendingID == before.pendingID)
        #expect(after.name == before.name)
        #expect(after.colorName == before.colorName)
        #expect(after.events.map(\.pendingID) == before.events.map(\.pendingID))
        #expect(after.events.map(\.name) == before.events.map(\.name))
        #expect(after.events.map(\.colorName) == before.events.map(\.colorName))
    }

    @Test("Midnight is how a time is cleared, and it needs no separate field")
    func midnightClearsTheTime() throws {
        let timed = selecting(editing(days: [1, 2]))
        let timedNext = reduce(timed, .applyTimeToSelectedEvents(clock(18))).next
        #expect(try hourAndMinute(#require(timedNext.assembly?.batch.events[0].date)) == (18, 0))

        // **Premise changed.** The second pick used to be sent on the state the first one
        // left behind. A pick now clears the selection, so a second pick needs a second
        // selection — which is what the editor makes the user do.
        let cleared = reduce(selecting(timedNext), .applyTimeToSelectedEvents(clock(0))).next

        for event in try #require(cleared.assembly?.batch.events) {
            #expect(hourAndMinute(event.date) == (0, 0))
            #expect(!provider.hasTimeOfDay(event.date), "midnight is this feature's 'unset'")
        }
    }

    @Test("A pick clears the selection, so the picker greys out again")
    func aPickIsOverWhenItIsWritten() {
        let state = selecting(editing(days: [1, 2, 3]), first: 0, count: 2)

        let next = reduce(state, .applyTimeToSelectedEvents(clock(9))).next

        #expect(next.selectedEventIDs.isEmpty)
        #expect(!next.isSelectingEvents)
    }

    @Test("Re-picking the time already stored writes nothing")
    func aPickThatChangesNothingIsNotAWrite() {
        let state = selecting(editing(days: [1, 2]))
        let timed = reduce(state, .applyTimeToSelectedEvents(clock(13, 45))).next

        // **Premise changed**, as above: the pick that re-picks has to re-select first.
        let (next, effects) = reduce(selecting(timed), .applyTimeToSelectedEvents(clock(13, 45)))

        #expect(next.batches == timed.batches)
        #expect(effects.isEmpty, "the row did not move, so there is nothing to persist")
    }

    @Test("A time survives a reload of the calendar")
    func timeSurvivesAReload() throws {
        let state = selecting(editing(days: [1, 2]))
        let timed = reduce(state, .applyTimeToSelectedEvents(clock(16, 20))).next

        // What a DTO round trip produces: same persisted id, same instants, fresh session ids.
        let reloaded = timed.batches.map {
            CalendarEventBatch(
                persistedID: $0.persistedID,
                name: $0.name,
                colorName: $0.colorName,
                events: $0.events
            )
        }
        let synced = pcEventSelectionReducer(timed, .syncCalendar(calendarID: 42, batches: reloaded))

        #expect(try hourAndMinute(#require(synced.assembly?.batch.events[0].date)) == (16, 20))
        #expect(
            synced.assembly?.mergeKey == timed.assembly!.mergeKey,
            "and the row it writes to is still the same one"
        )
    }

    @Test("The picker's displayed value is a real stored time")
    func pickerReadsFromTheSelection() throws {
        // Asserted on the state's derivation rather than through `AddEditEventBatchViewModel`,
        // which reads exactly this: the view model has no copy of its own to get wrong, and a
        // test that drove it would be testing the property it delegates to.
        var state = selecting(editing(days: [3, 1, 2]), first: 0, count: 1)
        #expect(state.selectedEvents.count == 1)

        state = reduce(state, .applyTimeToSelectedEvents(clock(7, 5))).next

        // **Premise changed.** Read off the assembly, not off `selectedEvents`: a pick clears
        // the selection now, so the selected events are gone by the time this asserts — and
        // the empty selection is what the picker greying out is made of.
        let picked = try #require(state.assembly?.batch.events.first)
        #expect(hourAndMinute(picked.date) == (7, 5))
        #expect(
            provider.hasTimeOfDay(picked.date),
            "the value the picker showed is stored, not a scratch value the user never chose"
        )
        #expect(state.selectedEventIDs.isEmpty, "and it is shown no longer — the gesture ended")
    }

    // MARK: Helpers

    private func dayOf(_ event: CalendarEvent) -> Int {
        provider.dateComponents(forDate: event.date).day ?? 0
    }

    /// The same event's day before the pick, matched by identity rather than by index.
    private func dayOf(previous: PCEventSelectionState, event: CalendarEvent) -> Int {
        let before = previous.assembly?.batch.events.first { $0.pendingID == event.pendingID }
        return provider.dateComponents(forDate: before?.date ?? event.date).day ?? 0
    }
}
