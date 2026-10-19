//
//  PCEventSelectionReducerTests.swift
//  SingleCalendarFeatureTests
//
//  Stage 5b's gate: §12.1. One test per row of the plan's §6.3 and §6.4 tables, plus the
//  cross-cutting rules — every action is covered, a rejected action is inert, a rejected
//  action emits nothing, and the reducer is a pure function of its two inputs.
//

import Foundation
import Testing
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
    /// `init` no longer re-stamps the zone and locale, so a fixture *can* pin them by
    /// passing its own `Calendar` — this one does not, and instead relies on the default
    /// following the device, so the tests assert in whatever zone they run in.
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
            // Sorted before the anchor is taken, and the loop toggles the *rest*.
            //
            // It used to anchor on `days.min()` and toggle `days.dropFirst()`, which silently
            // toggled the anchor back **off** whenever the first element was not the smallest:
            // `days: [6, 4]` anchored on the 4th and then "added" the 4th, leaving an empty
            // batch. Nothing noticed, because every assertion over a session read the *days*
            // or the *registry*, and neither of those is built from this assembly — the one
            // thing a fixture must not do is build a state the reducer cannot emit.
            let sorted = days.map(provider.startOfDay(for:)).sorted()
            var assembly = PCEventBatchAssembleUnitOfWork.new(
                anchor: sorted[0],
                colorName: color.colorName,
                using: provider
            )
            // One assembly for the session, built by toggling in the remaining days — the
            // same path the reducer takes, so the identity matches rather than being faked.
            for day in sorted.dropFirst() {
                assembly = assembly.toggling(day: day, using: provider)
            }
            #expect(
                assembly.batch.events.count == sorted.count,
                "the fixture must build the batch the reducer would, or it tests a state that cannot occur"
            )
            next.multiSelectAssembly = assembly
        }
        next.dayEventColors = next.derivedDayEventColors
        return next
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
                        persistedID: $0.persistedID ?? firstID + Int64(offset) * 1000,
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

    /// **Premise changed.** This asserted `effects.count == 1` — "tapping a day writes the new
    /// batch at once" — and the comment above it recorded having *reversed* that earlier
    /// decision ("Was 'staging is not a write'"). The reversal is what made a misclick
    /// permanent: the app's most common accident, on a grid of day cells, wrote a row before
    /// the user had decided they wanted one, and there is no undo for a batch anywhere.
    ///
    /// A tapped day is now a *draft*: staged, coloured, marked in the editor's calendar, and
    /// not written. `editing` merges it on the first real edit, and `pcEventSelectionEffects`
    /// writes exactly when the registry moved, so "not merged" is the whole of "not written" —
    /// there is no second mechanism to keep in step.
    @Test("Tapping an empty day stages a draft and writes nothing")
    func dayTappedEmptyDay() {
        let state = session(batches: [])
        let (next, effects) = reduce(state, .dayTappedInCalendar(day(4)))

        #expect(next.stage == .batchEditor)
        #expect(next.assembly != nil)
        #expect(next.day == day(4))
        #expect(next.scrollAnchor == day(4))
        #expect(next.editorYear == nil)
        #expect(next.assembly?.batch.name.isEmpty == true, "unnamed, which is what makes it a draft")
        #expect(
            next.assembly?.canSave == false,
            "an unnamed batch is not writable yet — naming it is what writes it, see `canSave`"
        )
        #expect(next.navigationRequest?.target == .presentBatchEditor)
        #expect(next.batches.isEmpty, "not merged, so the registry does not describe it")
        #expect(effects.isEmpty, "and nothing was written")
    }

    /// The other half of the same guarantee: a draft is promoted by the first edit, which is
    /// what makes "tap a day and walk away costs nothing" true without also making "tap a day
    /// and do anything is impossible".
    @Test("Naming a tapped day's batch is what writes it")
    func namingATappedDayPromotesTheDraft() {
        let tapped = reduce(session(batches: []), .dayTappedInCalendar(day(4))).next

        let (named, effects) = reduce(tapped, .setBatchName("Cycle"))

        #expect(named.batches.count == 1, "the draft joined the registry")
        #expect(named.batches.first?.name == "Cycle")
        #expect(
            effects == [.writeCalendar(calendarID: 42, numberOfColumns: 3, batches: named.batches)],
            "and that is the write. It is marked as typed, so the store holds it on the debounce."
        )
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

    /// The plus button is the other way to say "add a batch here", so it is held to the same rule
    /// as tapping the day cell. Treating it differently would mean the same accident is free
    /// through one door and permanent through the other.
    @Test("startNewBatch stages a draft and writes nothing")
    func startNewBatch() {
        let state = session(batches: [])
        let (next, effects) = reduce(state, .startNewBatch(on: day(9)))

        #expect(next.stage == .batchEditor)
        #expect(next.day == day(9))
        #expect(next.scrollAnchor == day(9))
        #expect(next.assembly?.batch.name.isEmpty == true)
        #expect(next.navigationRequest?.target == .presentBatchEditor)
        #expect(next.batches.isEmpty)
        #expect(effects.isEmpty, "the plus button writes its new batch on the first edit too")
    }

    @Test("openBatch stages the batch it found and asks for a sheet presentation")
    func openBatch() {
        let target = batch("morning", on: 1, id: 7)
        let (next, _) = reduce(session(batches: [target]), .openBatch(id: target.mergeKey))

        #expect(next.stage == .batchEditor)
        #expect(next.assembly?.batch.pendingID == target.pendingID)
        #expect(next.day == target.date)
        #expect(next.scrollAnchor == target.date)
        #expect(next.navigationRequest?.target == .presentBatchEditor)
    }

    /// The regression that made a card tap do nothing.
    ///
    /// `pendingID` is session identity and a DTO carries none, so every row is re-minted on
    /// every load — and the model re-syncs on every calendar write, so a write from
    /// anywhere re-mints the row a card on screen was drawn from. Opening by `pendingID`
    /// then missed, the action was rejected, and the tap was dropped with nothing logged.
    /// `mergeKey` survives, because the persisted id does.
    @Test("A reload re-mints every pendingID, and a card drawn before it still opens its row")
    func openBatchSurvivesAReload() {
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
        #expect(next.navigationRequest?.target == .presentBatchEditor)
    }

    @Test("openBatch with an unknown id is rejected")
    func openBatchUnknown() {
        let state = session()
        #expect(reduce(state, .openBatch(id: .pending(UUID()))).next == state)
        #expect(reduce(state, .openBatch(id: .persisted(999))).next == state, "no such row")
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
    func backFromBatchEditor() throws {
        let (next, _) = reduce(editing(session(), on: 1), .backTapped)

        #expect(next.assembly == nil, "the editor is closed")
        #expect(
            next.batches.contains { $0.name == "edited" },
            "the staged edit reached the registry rather than being dropped"
        )
        // Compared as a *day*, not as an instant. `day(1)` is noon UTC and a placeholder sits
        // at the start of its day, so the two denote the same day by different instants —
        // `dayBatches` matches with `isSameDay`, and only the day is the contract.
        let dayList = try #require(next.stage.asDayList)
        #expect(
            provider.isSameDay(dayList, day(1)),
            "returns to the day list for the day the batch is on, got \(dayList)"
        )
        // The editor is a sheet now, so leaving it is `.dismissBatchEditor`. The *stage* is
        // still the day list underneath — the sheet only covers it, it does not replace it.
        #expect(next.navigationRequest?.target == .dismissBatchEditor)
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

    /// The title has been right twice. The original report was that the editor opened with the
    /// tapped day unmarked, and then that backing out left a marker for an event that was never
    /// written — the first was fixed by projecting markers from the staged assembly, the second
    /// by making the tap write the batch so the marker would have been true.
    ///
    /// **Premise changed.** The second fix is gone, and with it the reason the marker used to
    /// survive: there is no longer a row behind it to be true about. A tapped day is a draft,
    /// so its mark is the editor's own projection of a staged assembly
    /// (`derivedDayEventColors` folds it in) and disappears with it. Both halves are asserted
    /// here, because a draft that was marked only after being written would be the same bug
    /// wearing the opposite sign — the editor showing a day it has not committed.
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
        #expect(
            back.dayEventColors[provider.startOfDay(for: day(9))] == nil,
            "and nothing was written, so there is no event for the marker to be about"
        )
        #expect(back.batches.isEmpty, "the draft never entered the registry")
    }

    /// Cancelling is Back's sibling and has to agree with it, or the same untouched draft would
    /// survive one exit route and not the other.
    @Test("Cancelling an untouched draft takes its marker with it")
    func startNewBatchThenCancelClearsMarker() {
        let empty = session(batches: [])

        let started = reduce(empty, .startNewBatch(on: day(9))).next
        #expect(started.stage == .batchEditor)
        #expect(
            started.dayEventColors[provider.startOfDay(for: day(9))] != nil,
            "the staged event must be marked in the editor's calendar"
        )

        let cancelled = reduce(started, .cancelTapped).next
        #expect(
            cancelled.dayEventColors[provider.startOfDay(for: day(9))] == nil,
            "nothing was written, so the marker has nothing behind it and goes"
        )
        #expect(cancelled.batches.isEmpty)
        #expect(cancelled.assembly == nil, "and the editor is closed")
    }

    /// The rule is anchored to "has not been written yet", not to "is empty right now". A batch
    /// the user names and then renames back to nothing is a real batch they made, and Back must
    /// not read the emptied name as an instruction to delete it.
    ///
    /// **Premise changed**, in the middle assertion. It used to end with `name.isEmpty == true`
    /// — "it is simply untitled now" — because erasing the name was an edit, and edits were
    /// written as they were made. It is not written now: an unnamed batch is a draft, and a
    /// draft is not merged. So the row keeps the name it was last written under, and the
    /// divergence is the price of the rule. It is a cheap one — the user sees their own name
    /// again, not a lost batch — and the alternative, rewriting the row untitled, is exactly
    /// the untitled row this requirement exists to prevent.
    @Test("A batch that was written and then had its name erased survives Back, still named")
    func erasingANameDoesNotDiscardAWrittenBatch() throws {
        let named = reduce(session(batches: []), .startNewBatch(on: day(9))).next
        let renamed = reduce(named, .setBatchName("Cycle")).next
        #expect(renamed.batches.count == 1, "setup: naming wrote it")

        let erased = reduce(renamed, .setBatchName("")).next
        #expect(erased.batches.count == 1, "erasing the name leaves the row alone")
        #expect(
            erased.assembly?.batch.name.isEmpty == true,
            "while the editor holds an untitled batch, which is a draft rather than an edit"
        )
        #expect(erased.assembly?.canSave == false, "so the erasure is not written")

        let back = reduce(erased, .backTapped).next
        #expect(back.batches.count == 1, "and so does leaving — the row is the user's work")
        #expect(
            back.batches.first?.name == "Cycle",
            "with the name it was written under: erasing it is not an edit that gets written, because an unnamed batch must not reach the database"
        )

        #expect(try back.stage == .dayList(day: #require(back.day)), "it lands on a day list")
        #expect(
            back.day == back.batches.first?.date,
            "re-anchored on the day the row is on, which is the invariant `backTapped` already claims"
        )
        #expect(
            back.dayEventColors[provider.startOfDay(for: day(9))] != nil,
            "so the day is still marked"
        )
    }

    @Test("removeEvent drops the event and its marker")
    func removeEvent() throws {
        let state = editing(session(), on: 1)
        let pendingID = try #require(state.assembly?.batch.events.first?.pendingID)
        let (next, effects) = reduce(state, .removeEvent(pendingID: pendingID))

        #expect(try #require(next.assembly).batch.events.isEmpty)
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
                CalendarEvent(name: "Event1", date: day(12), colorName: "eventColorOption1"),
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
    func removeEventFromOpenedBatchUnmarksTheDay() throws {
        let committed = twoDayBatch()
        let opened = reduce(session(batches: [committed]), .openBatch(id: committed.mergeKey)).next
        let pendingID = try #require(opened.assembly?.batch.events.first?.pendingID)

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

    // There is no event-editor section. It held five tests — `openEvent` carrying both ids into the
    // stage, an unknown id being rejected, the three field edits folding into the draft, Back
    // keeping the edit while dropping the draft, and `discardEventTapped` undoing it. Every one
    // of them needed the screen, and with it gone an event has no name, colour or date of its
    // own to edit: `toggling` appends a placeholder and the batch editor's colour reaches it.

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
    func backReanchorsOnTheRowsDay() throws {
        // A committed batch on the 10th, 11th, 12th and 13th.
        let committed = CalendarEventBatch(
            persistedID: 7,
            name: "Window",
            colorName: "eventColorOption1",
            events: (10...13).map { CalendarEvent(name: "Event", date: day($0), colorName: "eventColorOption1") }
        )
        let opened = reduce(session(batches: [committed]), .openBatch(id: committed.mergeKey)).next
        #expect(
            try provider.isSameDay(#require(opened.day), day(10)),
            "setup: the session opens on the row's first day"
        )

        // Remove the 10th, 11th and 12th, leaving the 13th — §16's step 6.
        var staged = opened
        for d in [10, 11, 12] {
            staged = reduce(staged, .toggleDay(day(d))).next
        }
        #expect(try #require(staged.assembly?.batch).events.count == 1, "setup: one event left")

        let (next, _) = reduce(staged, .backTapped)

        #expect(
            try provider.isSameDay(#require(next.day), day(13)),
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
    ///
    /// **Premise changed.** This relied on the creation step writing the row ("setup: creation
    /// wrote the row"). It does not any more: a new batch is born unnamed and stays a draft
    /// until it is edited, so the test now names it — which is what a real user's first
    /// keystroke does.
    @Test("Leaving an emptied batch editor deletes the row and unwinds to the root")
    func backFromEmptiedBatchEditorDeletes() throws {
        // Built through `startNewBatch` rather than the `editing` fixture, because the claim
        // being made is about a row that is *in the registry* — the fixture stages an assembly
        // without merging it, which the reducer cannot produce and which would make "the row
        // outlives the removal" vacuous.
        let created = reduce(session(batches: []), .startNewBatch(on: day(1))).next
        let written = reduce(created, .setBatchName("Cycle")).next
        let pendingID = try #require(written.assembly?.batch.events.first?.pendingID)
        #expect(written.batches.count == 1, "setup: naming the batch wrote the row")

        let emptied = reduce(written, .removeEvent(pendingID: pendingID)).next

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
    ///
    /// **Premise changed.** This staged a fresh `new(anchor:colorName:"")` and asserted the row
    /// it "created" was still there. There was no such row: with no colour `canSave` is false,
    /// so it was never merged, and the count of 1 was the unrelated batch the `session()`
    /// fixture carries. It is now staged as `existing`, which is the case the test is really
    /// about — a row that is already in the registry and unwritable, as a reload returning one
    /// would give. A new uncoloured batch cannot reach that state at all, so under the draft
    /// rule it correctly leaves to the calendar instead of to a day list that would be empty.
    @Test("Leaving an uncoloured but non-empty batch does not delete it")
    func backFromUnwritableBatchKeepsIt() {
        let stored = Fixture.batch("kept", on: 3, id: 11, color: "")
        var state = session(batches: [stored])
        state.assembly = PCEventBatchAssembleUnitOfWork.existing(stored)
        state.stage = .batchEditor
        state.day = day(3)
        state.dayEventColors = state.derivedDayEventColors

        let (next, effects) = reduce(state, .backTapped)

        #expect(next.assembly == nil, "it does close the editor")
        #expect(next.batches.count == 1, "but the row is still there")
        #expect(next.batches.first?.persistedID == 11, "and it is the same row, not a replacement")
        #expect(next.stage == .dayList(day: day(3)))
        #expect(effects.isEmpty)
    }

    /// The write that has landed while the editor is still open must not be duplicated on the
    /// way out.
    ///
    /// This is a race, and races are the ones that ship. Naming a batch writes it on a debounce;
    /// leaving the editor merges the staged row again. If the write has landed and its reload
    /// has already replaced the registry, the assembly is still keyed `pending(…)` — adoption
    /// happens on that reload, and a reload that arrived *before* the write had nothing to
    /// adopt — so the merge is keyed differently from the row it is merging, and appends. One
    /// batch, two rows, one day listing it twice. Measured on iPhone: the same test passes
    /// alone and fails inside the full UI run, which is what a race looks like from outside.
    ///
    /// The state is built by hand rather than driven, because the reducer cannot produce it:
    /// `syncCalendar` adopts on every reload, so there is no sequence of actions that ends with
    /// a landed write, a registry holding it, and an assembly that never learned its id. That
    /// is exactly the state the race leaves behind, and it is the only honest way to pin the
    /// merge.
    @Test("Leaving the editor does not duplicate a batch whose write has already landed")
    func leavingAnEditorDoesNotDuplicateALandedWrite() throws {
        // The row the store gave back: a real id, and a fresh `pendingID`, because the mapper
        // mints one for every row on every load.
        //
        // Same name, same colour and the same day as the staged assembly below, because that
        // is what content matching compares. Getting it wrong here does not make the test
        // fail loudly — it makes it pass for the wrong reason, which is why the colours are
        // written out rather than left to two different defaults.
        let staged = PCEventBatchAssembleUnitOfWork.new(
            anchor: day(9),
            name: "Cycle",
            colorName: "eventColorOption2",
            using: provider
        )
        // The row that write produced, as the reload hands it back: a real id, a fresh
        // `pendingID` (the mapper mints one per row per load), and otherwise identical
        // content — which includes the placeholder event's *name*, since that is part of what
        // `hasSameContent` compares. Building the row from the assembly rather than by hand is
        // what guarantees it; a hand-written twin can differ in a field the matcher reads, and
        // then the test passes for the wrong reason.
        let written = try reloaded([#require(staged.resolved())])
        var state = session(batches: written)
        // The staged assembly, still holding the `.pending(…)` key it was created with.
        state.assembly = staged
        state.stage = .batchEditor
        state.day = day(9)
        state.dayEventColors = state.derivedDayEventColors

        #expect(state.batches.count == 1, "setup: the write has landed")
        #expect(state.assembly?.mergeKey != state.batches.first?.mergeKey, "setup: two keys, one batch")

        #expect(
            state.assembly?.batch.hasSameContent(as: state.batches[0], using: provider) == true,
            "setup: the registry row and the staged assembly describe one batch, by content"
        )
        #expect(state.assembly?.canSave == true, "setup: it is named and coloured, so leaving would merge it")
        let back = reduce(state, .backTapped).next

        #expect(
            back.batches.count == 1,
            "one batch, not the same batch twice — got \(back.batches.count)"
        )
        #expect(
            back.batches.first?.persistedID == written.first?.persistedID,
            "and it is still the written row, adopted rather than replaced by a pending one"
        )
    }

    /// The draft branch on Back: a batch staged by a tap and left alone was never merged, so
    /// Back does not promote it on the way out — and unwinds to the calendar rather than to the
    /// day's list, which would be empty for a batch the user does not have.
    @Test("Leaving an untouched draft unwinds to the calendar, not to an empty day list")
    func backFromUntouchedDraftUnwindsToTheCalendar() {
        let tapped = reduce(session(batches: []), .dayTappedInCalendar(day(9))).next

        let (next, effects) = reduce(tapped, .backTapped)

        #expect(next.assembly == nil)
        #expect(next.stage == .idle, "not a day list: there is no batch on that day to list")
        #expect(next.day == nil)
        #expect(next.batches.isEmpty)
        #expect(effects.isEmpty, "and nothing was written, so there is nothing to delete")
        #expect(next.navigationRequest?.target == .popToCalendarRoot)
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
        #expect(next.multiSelectAssembly?.batch.colorName == PCColorOption.option3.colorName, "and the batch takes it")
        // Was once the opposite twice over. It began as "a colour choice is not a write" —
        // true while a session's days were staged and nothing existed on disk. It was then
        // changed to *expect* a write, because the session wrote its batch on the first tap
        // and recolouring it is a write. A session writes nothing now, so it is a write
        // again for the same reason it was not one the first time: the batch it holds is
        // still a draft, and repainting a draft is not persistence.
        #expect(effects.isEmpty, "recolouring a session's draft batch writes nothing")
        #expect(
            next.dayEventColors.values.flatMap { $0 }.contains(PCColorOption.option3.colorName),
            "though the days do take the new colour — the markers are projected from the session"
        )
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
        #expect(
            second.batches.count == 1,
            "still just the committed one — a session writes nothing, so there is nothing to add"
        )
        let grown = try #require(second.multiSelectAssembly)
        #expect(grown.batch.events.count == 3, "and it grew to three days")
    }

    /// Three taps, one batch — held in the session rather than in the registry.
    ///
    /// **Premise changed.** This asserted `state.batches.count == 1` after three taps, and it
    /// was the regression guard for the §6.5 bug: tapping 17, 18 and 19 produced three
    /// batches, the first holding three events, the second two, the third one. The signature
    /// was cumulative, which is what a batch *rebuilt* per tap looks like — a fresh
    /// `pendingID` each time, so a different `mergeKey`, landing beside the last instead of
    /// replacing it.
    ///
    /// A session no longer merges per tap, so the registry cannot grow at all and the count
    /// is no longer the thing that would catch that bug. The assembly is: one object, one
    /// `pendingID`, holding all three days. That is the same invariant one level up, and it
    /// is the level the bug now has to break at.
    @Test("Tapping three days in a session leaves exactly one staged batch with three events")
    func threeTappedDaysProduceOneBatch() throws {
        var state = multiSelecting(session(batches: []), days: [], color: .option2)

        for day in [day(17), day(18), day(19)] {
            state = reduce(state, .dayTappedInCalendar(day)).next
        }

        #expect(state.batches.isEmpty, "three taps wrote nothing — an unnamed batch is a draft")
        let assembly = try #require(state.multiSelectAssembly)
        #expect(
            assembly.batch.events.map(\.date) == [day(17), day(18), day(19)].map(provider.startOfDay(for:)),
            "holding all three days, not a growing pile"
        )
        #expect(assembly.batch.colorName == "eventColorOption2", "in the chosen colour")
        #expect(assembly.batch.name.isEmpty, "and still unnamed, which is why nothing is written")
        #expect(assembly.canSave == false)
    }

    /// The same three taps, with a reload between each — the timing that produced the §6.5
    /// bug, and it is still worth driving.
    ///
    /// **Premise changed.** The bug was that a session wrote per tap, so every tap triggered
    /// a reload, `syncCalendar` replaced `batches` wholesale with rows carrying real ids, and
    /// the session's `.pending(…)` key answered to nothing after the first — so every tap
    /// after it appended. The fix was adoption, and this test is why it shipped.
    ///
    /// A session writes nothing now, so there is no per-tap reload to survive, and adoption
    /// has nothing to adopt until Confirm. The bug cannot reproduce in this shape, which
    /// makes the test assert the *reason*: the registry is untouched by a reload because
    /// nothing was ever put in it, and the session's days survive on the assembly alone.
    @Test("A reload during a session cannot split it, because a session writes nothing")
    func reloadBetweenTapsLeavesOneBatch() throws {
        var state = multiSelecting(session(batches: []), days: [], color: .option2)

        for tapped in [day(17), day(18), day(19)] {
            state = reduce(state, .dayTappedInCalendar(tapped)).next
            // Exactly what the store does after a write: read the calendar back and hand the
            // rows over, ids and all. Nothing changed, so nothing comes back.
            state = reduce(state, .syncCalendar(calendarID: 42, batches: reloaded(state.batches))).next
        }

        #expect(state.batches.isEmpty, "three taps and three reloads wrote nothing at all")
        let assembly = try #require(state.multiSelectAssembly)
        #expect(
            assembly.batch.events.map { provider.startOfDay(for: $0.date) }
                == [day(17), day(18), day(19)].map(provider.startOfDay(for:)),
            "holding all three days — the session's days live here, not in the registry"
        )
        #expect(
            assembly.adoptedPersistedID == nil,
            "and there is no id to adopt, because there is no row of its own"
        )
        #expect(state.dayEventColors.count == 3, "the three days stay marked throughout")
    }

    /// The mid-round-trip tap — the timing that decided whether §6.5 showed up at all.
    ///
    /// **Premise changed.** This drove two taps and one reload so the database held the
    /// one-day shape while the session held two, and asserted the stale shape was dropped
    /// rather than kept beside the live one, painting its day twice.
    ///
    /// With nothing written there is no stale shape: the "reload" hands back an empty
    /// registry, and what is asserted instead is the property that makes the race
    /// impossible — one marker per day, however many reloads pass.
    @Test("A reload landing mid-session cannot leave a stale shape behind")
    func tapArrivingMidRoundTripDoesNotLeaveASnapshot() throws {
        var state = multiSelecting(session(batches: []), days: [], color: .option2)

        // Two taps, then *one* reload — the second tap used to beat the first write home.
        state = reduce(state, .dayTappedInCalendar(day(17))).next
        state = reduce(state, .dayTappedInCalendar(day(18))).next
        state = reduce(state, .syncCalendar(calendarID: 42, batches: reloaded(state.batches))).next

        #expect(state.batches.isEmpty, "nothing to strand — the registry never held a session row")
        let assembly = try #require(state.multiSelectAssembly)
        #expect(assembly.batch.events.count == 2, "on both days")
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
    ///
    /// **Premise changed.** The two batches here are both named "New event", which is what an
    /// untouched batch used to be called — and a session that taps a day holding one of those
    /// used to *adopt* it, because name plus colour plus day matched by content. That was the
    /// weak-identity problem this very test exists to guard against, showing up as a feature:
    /// a session starting on a day that already had a batch silently overwrote it instead of
    /// adding a second one. An unnamed session batch no longer matches it, so the session
    /// builds its own row and the pre-existing batch is left alone — which is what the
    /// neighbour assertion has always asked for, now applied to the same-day case too.
    @Test("A session's reload leaves unrelated rows alone")
    func sessionReloadDoesNotTouchUnrelatedRows() {
        // Two "New event" batches in the chosen colour, one on a day the session holds and
        // one on a day it does not. The second is the row that must survive.
        var state = session(batches: [
            Fixture.batch("New event", on: 17, id: 1, color: "eventColorOption2"),
            Fixture.batch("New event", on: 21, id: 2, color: "eventColorOption2"),
        ])
        state = multiSelecting(state, days: [], color: .option2)
        state = reduce(state, .dayTappedInCalendar(day(17))).next

        state = reduce(state, .syncCalendar(calendarID: 42, batches: reloaded(state.batches))).next

        #expect(
            state.batches.contains { $0.events.contains { provider.isSameDay($0.date, day(21)) } },
            "day 21 still has its batch"
        )
        #expect(
            state.batches.contains { $0.events.contains { provider.isSameDay($0.date, day(17)) } && !$0.name.isEmpty },
            "and so does the pre-existing batch on day 17 — the session did not adopt it"
        )
    }

    /// A session has no row of its own to adopt.
    ///
    /// **Premise changed.** This was the adoption case the §6.5 fix rested on: the session
    /// wrote a row, the write came back under a real id, and the session had to settle on it
    /// or the next tap would append a second one.
    ///
    /// Nothing is written during a session now, so there is no row, no id, and nothing to
    /// adopt — and, more usefully, nothing for content-based matching to mistake for its own.
    /// A session can no longer collide with an unrelated untitled batch across a reload,
    /// because the reload carries no row it could be mistaken for.
    @Test("A session has no row to adopt, because it writes none")
    func sessionAdoptsItsOwnUnnamedRow() {
        var state = multiSelecting(session(batches: []), days: [], color: .option2)
        state = reduce(state, .dayTappedInCalendar(day(17))).next
        #expect(state.multiSelectAssembly?.batch.name.isEmpty == true, "setup: a session's batch is unnamed")

        let reloadedState = reduce(state, .syncCalendar(calendarID: 42, batches: reloaded(state.batches))).next

        #expect(reloadedState.batches.isEmpty, "and the reload has nothing to hand back")
        #expect(
            reloadedState.multiSelectAssembly?.adoptedPersistedID == nil,
            "so nothing was adopted — content matching has no candidate of its own"
        )
        #expect(
            reloadedState.multiSelectAssembly?.batch.pendingID == state.multiSelectAssembly?.batch.pendingID,
            "the session's identity is untouched by the round trip"
        )
    }

    /// Two untitled batches in the same colour are now the *common* case rather than an exotic
    /// one, because a batch that was written and then had its name erased looks exactly like a
    /// freshly-created one. They must not be able to adopt each other across a reload, which is
    /// the collision `isSnapshot`-based matching is vulnerable to.
    @Test("Two untitled batches are not confused with each other by a reload")
    func untitledBatchesDoNotCollideAcrossAReload() {
        let first = Fixture.batch("", on: 17, id: 1, color: "eventColorOption2")
        let second = Fixture.batch("", on: 21, id: 2, color: "eventColorOption2")

        let state = reduce(
            session(batches: [first, second]),
            .syncCalendar(calendarID: 42, batches: [Fixture.batch("", on: 17, id: 1, color: "eventColorOption2"), Fixture.batch("", on: 21, id: 2, color: "eventColorOption2")])
        ).next

        #expect(state.batches.count == 2, "both rows survive — got \(state.batches.count)")
        #expect(state.batches.contains { $0.persistedID == 1 })
        #expect(state.batches.contains { $0.persistedID == 2 })
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

    /// Toggling the last day back off takes the day off the calendar.
    ///
    /// **Premise changed.** This needed a branch that does not exist any more, and it is worth
    /// saying what that branch was for. A session used to write on every tap, so a session with
    /// no Back button and no Save had to handle an emptied batch itself: `resolved()` is
    /// `nil` for it, the registry kept the last row written, and the day stayed coloured in
    /// the database after the user had deselected it.
    ///
    /// With nothing written there is no row to remove, and the marker goes because the marker
    /// was always projected from the selection rather than read off a row. The assertion that
    /// matters is the one about the day, not the registry: an emptied session must paint
    /// nothing.
    @Test("Toggling every day back off takes the session's days off the calendar")
    func multiSelectTogglingTheLastDayOffDeletesTheBatch() {
        var state = multiSelecting(session(batches: []), days: [], color: .option2)
        state = reduce(state, .dayTappedInCalendar(day(17))).next
        #expect(state.dayEventColors.count == 1, "setup: the tapped day is marked")
        #expect(state.batches.isEmpty, "setup: and nothing was written for it")

        state = reduce(state, .dayTappedInCalendar(day(17))).next

        #expect(state.multiSelectDays.isEmpty)
        #expect(state.multiSelectAssembly?.batch.isEmpty == true, "the batch is empty")
        #expect(state.batches.isEmpty, "and there was never a row to remove")
        #expect(state.dayEventColors.isEmpty, "the day loses its marker")
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
    func confirmingAnEmptiedSessionLeavesNoBatch() {
        var state = multiSelecting(session(batches: []), days: [], color: .option2)
        state = reduce(state, .dayTappedInCalendar(day(17))).next
        #expect(state.dayEventColors.count == 1, "setup: the tap marked the day")

        // The second tap takes the day back off. Nothing was written, so there is no row to
        // come back with an id — the emptiness below has to be reached by declining, not by
        // deleting.
        state = reduce(state, .dayTappedInCalendar(day(17))).next
        #expect(state.batches.isEmpty, "setup: nothing was ever written")
        #expect(state.dayEventColors.isEmpty, "setup: and the day is unmarked again")

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
        #expect(
            next.navigationRequest == nil,
            "an emptied session has nothing to review, so Confirm opens no editor"
        )
        #expect(effects.isEmpty, "there was no row, so there is nothing to write")
        #expect(
            next.dayEventColors.isEmpty,
            "so nothing is marked — an empty batch paints nothing, but it should not be here to paint"
        )
    }

    /// **Premise changed.** This asserted the opposite of what Confirm does now: it was named
    /// "ends the session without opening the editor" and said why — "the days were written as
    /// they were tapped, so Save has nothing to commit".
    ///
    /// They are no longer written as they are tapped. A session's batch is unnamed until
    /// someone names it, so Confirm is the door into the editor that asks for the name, and
    /// from there the rules are the ones for creating a batch.
    @Test("confirmMultiSelectTapped ends the session and opens the batch editor on it")
    func confirmMultiSelectEndsTheSession() throws {
        let state = multiSelecting(session(), days: [day(6), day(4)], color: .option2)
        let (next, effects) = reduce(state, .confirmMultiSelectTapped)

        #expect(!next.multiSelectMode, "single-select after Save")
        #expect(next.multiSelectDays.isEmpty)
        #expect(next.multiSelectColor == nil)
        #expect(next.multiSelectAssembly == nil, "the scratchpad is released")
        let assembly = try #require(next.assembly, "the session became the batch being edited")
        #expect(
            assembly.batch.events.count == 2,
            "holding both selected days — the editor reviews the batch the taps built"
        )
        #expect(next.stage == .batchEditor)
        #expect(next.navigationRequest?.target == .presentBatchEditor, "Confirm is now a navigation")
        #expect(effects.isEmpty, "and still writes nothing: the batch is still unnamed")
        #expect(
            assembly.origin == .new,
            "handed over as a new batch, not as an existing one — otherwise Back would write an unnamed row"
        )
        #expect(assembly.isDraft, "so leaving without naming it writes nothing, exactly like a tapped day")
    }

    @Test("Confirming ends the session, so the calendar behind the editor is not left mid-selection")
    func confirmMultiSelectClearsTheSession() {
        var state = multiSelecting(session(), days: [day(4), day(5)])
        state.multiSelectColor = .option1

        let next = reduce(state, .confirmMultiSelectTapped).next

        #expect(!next.multiSelectMode)
        #expect(next.multiSelectDays.isEmpty)
        #expect(next.multiSelectColor == nil)
        #expect(next.assembly != nil, "the session became the staged batch, not a discarded one")
        #expect(
            next.navigationRequest?.target == .presentBatchEditor,
            "and the editor is open on it, which is where the name is asked for"
        )
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

    /// Save with nothing selected still ends the session — it just opens nothing.
    ///
    /// **Premise changed**, twice over. It was first rejected outright, because it used to
    /// build a batch and open an editor for it; then it built nothing and only closed the
    /// session, and the name said "is rejected" while nothing was rejected; now it opens the
    /// editor, so the question is again what it does when there is nothing to review.
    ///
    /// The answer is the same as it was: end the session, open nothing, write nothing. An
    /// editor over an empty batch is the state that has no user-visible meaning at all.
    @Test("confirmMultiSelectTapped with nothing to save ends the session and opens nothing")
    func confirmMultiSelectIsRejected() {
        let committed = session()

        let uncoloured = multiSelecting(committed, days: [day(4)], color: nil)
        let afterUncoloured = reduce(uncoloured, .confirmMultiSelectTapped).next
        #expect(!afterUncoloured.multiSelectMode, "the session ended")
        #expect(afterUncoloured.batches == committed.batches, "and no batch was invented")
        #expect(
            afterUncoloured.navigationRequest == nil,
            "an uncoloured session has no days — the tap guard means one cannot happen, but a stale one opens nothing"
        )

        var empty = multiSelecting(committed, days: [], color: .option1)
        empty.multiSelectAssembly = nil
        let afterEmpty = reduce(empty, .confirmMultiSelectTapped).next
        #expect(!afterEmpty.multiSelectMode, "the session ended")
        #expect(afterEmpty.batches == committed.batches, "and nothing was written")
        #expect(afterEmpty.assembly == nil, "with no assembly there is nothing to stage")
        #expect(afterEmpty.navigationRequest == nil, "so no editor is opened")

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
    /// particular state: `openBatch` is looked up by `mergeKey`, `removeEvent` and
    /// `toggleEventSelection` by `pendingID`, so a fixed random id would simply miss and the
    /// action would look unhandled when it is in fact merely pointed at nothing.
    @Test("Every action is covered: it either changes state or emits an effect")
    func everyActionIsCovered() throws {
        let idle = session()
        let editing = editing(idle, on: 1)
        let multi = multiSelecting(idle, days: [day(4)])
        // `confirmMultiSelectTapped` needs a session that has days in it: it stages the batch
        // and opens the editor on it, and an uncoloured session stages nothing (the colour is
        // what gates a *tap*, so there are no days to stage), so confirming one is inert and
        // this test would rightly report it unexercised. Not because a colour is declined —
        // it used to be, and that guard is gone.
        var multiColoured = multi
        multiColoured.multiSelectColor = .option3

        let openable = idle
        let openableKey = try #require(openable.batches.first?.mergeKey)
        // The time picker's action needs a *selection* to act on, and `everyActionIsCovered`
        // is exactly the test that would otherwise report it as unreachable code: nothing else
        // here builds a selection first.
        var multiDayEditing = editing
        multiDayEditing.selectedEventIDs = Set(multiDayEditing.assembly?.batch.events.map(\.pendingID) ?? [])
        let openableEvent = editing.assembly.map { try! #require($0.batch.events.first?.pendingID) } ?? UUID()

        let cases: [(name: String, state: PCEventSelectionState, action: PCEventSelectionAction)] = try [
            ("ensureAssemblyStarted", editing, .ensureAssemblyStarted),
            ("dayTappedInCalendar", idle, .dayTappedInCalendar(day(4))),
            ("startNewBatch", idle, .startNewBatch(on: day(4))),
            ("openBatch", openable, .openBatch(id: openableKey)),
            ("backTapped", editing, .backTapped),
            ("closeTapped", editing, .closeTapped),
            ("cancelTapped", editing, .cancelTapped),
            ("navigationRequestHandled", editing, .navigationRequestHandled),
            ("setBatchName", editing, .setBatchName("n")),
            ("setBatchColor", editing, .setBatchColor(.option1)),
            ("toggleDay", editing, .toggleDay(day(5))),
            ("removeEvent", editing, .removeEvent(pendingID: #require(editing.assembly?.batch.events.first?.pendingID))),
            ("setEventSelectionMode", editing, .setEventSelectionMode(true)),
            ("toggleEventSelection", editing, .toggleEventSelection(pendingID: openableEvent)),
            ("selectAllEvents", editing, .selectAllEvents),
            // Needs a selection to clear: run against a state that has one, or the action is
            // legitimately inert and `everyActionIsCovered` reports it as unexercised — which
            // is the test doing its job, not a fixture that needs loosening.
            ("clearEventSelection", multiDayEditing, .clearEventSelection),
            ("applyTimeToSelectedEvents", multiDayEditing, .applyTimeToSelectedEvents(day(4))),
            ("deleteBatches", idle, .deleteBatches(idle.batches)),
            ("setMultiSelectMode", idle, .setMultiSelectMode(true)),
            ("setMultiSelectColor", idle, .setMultiSelectColor(.option2)),
            ("confirmMultiSelectTapped", multiColoured, .confirmMultiSelectTapped),
            ("cancelMultiSelectTapped", multi, .cancelMultiSelectTapped),
            ("setNumberOfColumns", idle, .setNumberOfColumns(4)),
            ("setEditorYear", idle, .setEditorYear(2027)),
            ("setScrollAnchor", idle, .setScrollAnchor(day(6))),
            ("syncCalendar", idle, .syncCalendar(calendarID: 42, batches: [batch("x", on: 1, id: 1)])),
            ("resetSession", editing, .resetSession),
        ]

        // Two actions are *supposed* to change nothing, so the rule cannot be "every
        // action must do something" — it is "every action is either exercised or
        // deliberately inert". `ensureAssemblyStarted` is a no-op by design, and
        // `navigationRequestHandled` on a state with no pending request has nothing to
        // clear. Both are asserted inert in their own tests.
        let inertByDesign: Set = ["ensureAssemblyStarted", "navigationRequestHandled"]

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
        can exercise. Since §6.2 the list also grew by five: the event selection and the \
        time it applies. It has since lost five more, with the event editor: `openEvent`, \
        `setEventName`, `setEventDate`, `setEventColor` and `discardEventTapped` had a screen \
        and no longer do.
        """)
        #expect(cases.count == 27, message)
    }

    @Test("A rejected action leaves the state byte-identical")
    func rejectedActionsAreInert() {
        let state = session()

        // The two the plan names explicitly.
        #expect(reduce(state, .setBatchName("n")).next == state, "no assembly")

        // And the rest of the guarded ones.
        #expect(reduce(state, .setBatchColor(.option1)).next == state)
        #expect(reduce(state, .removeEvent(pendingID: UUID())).next == state, "unknown event")
        #expect(reduce(state, .toggleDay(day(5))).next == state)
        #expect(reduce(state, .backTapped).next == state)
        #expect(reduce(state, .openBatch(id: .pending(UUID()))).next == state)
    }

    @Test("A rejected action emits no navigation and no effect")
    func rejectedActionsAreSilent() {
        let state = session()

        for (name, action) in allActions {
            let next = pcEventSelectionReducer(state, action)
            guard next == state else { continue } // not rejected, so out of scope
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

    /// The §6.2 case list, less the three that went with the checkmarks and the five that went
    /// with the event editor. These walks run against a plain session, so the multi-select
    /// cases are exercised in their *rejected* form here; the accepted form is covered by
    /// `everyActionIsCovered` and the dedicated multi-select tests.
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
            ("deleteBatches", .deleteBatches([])),
            ("setMultiSelectMode", .setMultiSelectMode(true)),
            ("setMultiSelectColor", .setMultiSelectColor(.option1)),
            ("confirmMultiSelectTapped", .confirmMultiSelectTapped),
            ("cancelMultiSelectTapped", .cancelMultiSelectTapped),
            ("setNumberOfColumns", .setNumberOfColumns(4)),
            ("setEditorYear", .setEditorYear(2027)),
            ("setScrollAnchor", .setScrollAnchor(day(6))),
            ("syncCalendar", .syncCalendar(calendarID: 42, batches: [batch("x", on: 1, id: 1)])),
            ("resetSession", .resetSession),
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
