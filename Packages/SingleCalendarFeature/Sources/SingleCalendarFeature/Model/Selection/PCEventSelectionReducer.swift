//
//  PCEventSelectionReducer.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 28.09.2026.
//

import Foundation
import CoreDomain
import DSKit

/// The only place `PCEventSelectionState` changes.
///
/// No `self`, no clock, no I/O. The one thing it does besides arithmetic is set a
/// `navigationRequest` for the view layer, which is still just a value in state.
///
/// A declared `func` rather than the plan's `public let reducer: (State, Action) -> State`
/// closure. A global `let` of function type has to be `Sendable` in Swift 6, which would
/// force `PCEventSelectionState` to be `Sendable`, which would force
/// `PCCalendarDataProvider` to be — and it wraps `Foundation.Calendar`. The function form
/// is identical to every caller and asks for none of that.
///
/// **One impurity, deliberate.** An action that starts a batch mints a fresh `pendingID`,
/// because `pendingID` *is* session identity and a new batch needs a new one. So two runs
/// of `dayTappedInCalendar` on the same state differ in that field and nothing else. The
/// tests assert determinism with the ids normalised rather than pretending it is total.
///
/// ## Rejected actions
///
/// Every guard that fails leaves the state byte-identical and emits no navigation. That is
/// the important property: a stray action — a double tap, an event arriving for a batch
/// that was just committed — cannot destroy committed work. So a `break` in here is a
/// *decision*, not an oversight.
public func pcEventSelectionReducer(
    _ state: PCEventSelectionState,
    _ action: PCEventSelectionAction
) -> PCEventSelectionState {
    var next = state
    let provider = state.dataProvider

    switch action {
    // MARK: Entry

    case .ensureAssemblyStarted:
        // No change, by design. See the action's declaration.
        break

    case let .dayTappedInCalendar(day):
        if state.multiSelectMode {
            // No colour, no batch — and this check sits *above* the selection, not below it.
            //
            // It used to guard only the write, after `multiSelectDays` had already recorded
            // the day, which read as "refuse to build a batch" while actually accepting the
            // selection and holding nothing to back it. The days were invisible too:
            // `derivedDayEventColors` needs a colour to paint from, so a session with days
            // and no colour showed nothing at all. Choosing a colour then painted them, in
            // that colour, with no batch behind them — four tapped days and an empty day
            // list, and nothing to tell the user why.
            //
            // Choosing the colour is the gesture that starts the batch, so before it a tap
            // is not a selection. It is inert rather than an error: a rejected action
            // leaves the state byte-identical and emits no navigation, which is the
            // contract the rest of this switch is written against.
            guard let color = state.multiSelectColor else { break }
            // Normalise the tap before comparing: what is stored is a start-of-day, and
            // comparing a start-of-day against a raw instant invites the two to disagree
            // about which day they name.
            let target = provider.startOfDay(for: day)
            if next.multiSelectDays.contains(where: { provider.isSameDay($0, target) }) {
                next.multiSelectDays.removeAll { provider.isSameDay($0, target) }
            } else {
                next.multiSelectDays.append(target)
            }
            // One assembly for the whole session, so the batch has one identity and each tap
            // updates it rather than adding another. Created on the first day, then toggled —
            // `toggling` preserves `pendingID`, which is what keeps the merge key stable.
            let assembly: PCEventBatchAssembleUnitOfWork
            if let existing = next.multiSelectAssembly {
                assembly = existing.toggling(day: target, using: provider)
            } else {
                assembly = PCEventBatchAssembleUnitOfWork.new(
                    anchor: next.multiSelectDays.min() ?? target,
                    colorName: color.colorName,
                    using: provider
                )
            }
            next.multiSelectAssembly = assembly
            // **Not merged, and deliberately.** A session's batch is unnamed until someone
            // names it, and an unnamed batch is not written (`canSave`) — so merging here
            // would write a row the editor is about to be asked to justify, and Confirm would
            // hand the user an editor for something already durable.
            //
            // It used to merge on every tap, on the reasoning that "written as it changes"
            // leaves Save nothing to commit. That reasoning assumed the batch was already a
            // batch. Now it is not until it is named, so the tap is a *selection*, and the
            // days are held in `multiSelectDays` + `multiSelectAssembly`.
            //
            // The days stay painted regardless: `derivedDayEventColors` projects the session
            // itself — days and colour — rather than reading a row, which is exactly why that
            // projection takes a `multiSelect:` argument. A session with no row and no
            // markers would look like four taps that did nothing.
        } else if state.batches.contains(where: { $0.occurs(on: day, using: provider) }) {
            next.day = day
            next.stage = .dayList(day: day)
            next.assembly = nil
            requesting(&next, .pushDayList)
        } else {
            next.day = day
            // Staged **unnamed**, so a merely-tapped day is still a draft and nothing is
            // written for it yet.
            //
            // It used to be named `defaultBatchName` and merged immediately, on the reasoning
            // that tapping a day is a decision to add a batch and is already fully determined
            // by a day and the default colour. That reasoning was sound and the consequence
            // was not: it made the app's single most common mistake permanent. A misclick on a
            // day cell — which is easy, because the calendar is a grid of them — wrote a batch
            // to ObjectBox before the user had decided they wanted one, and `deleteBatches` has
            // no undo anywhere in the app, so the only recovery was tapping the day, the day
            // list, the batch, and deleting, four taps to undo one.
            //
            // The write is implied by the row being *merged* (see `pcEventSelectionEffects`),
            // so not merging is the whole of not writing: there is no flag and no second path.
            // The first real edit — a name, a colour, a day, a time — goes through `editing`
            // and merges as it always did, and the batch becomes real at that moment rather
            // than at the tap.
            //
            // The day stays marked while the editor is open either way: `derivedDayEventColors`
            // folds the staged assembly in, so the calendar does not look like the tap did
            // nothing.
            next.assembly = PCEventBatchAssembleUnitOfWork.new(anchor: day, using: provider)
            next.stage = .batchEditor
            next.scrollAnchor = day
            next.editorYear = nil
            endingEventSelection(&next)
            requesting(&next, .presentBatchEditor)
        }

    case let .startNewBatch(on: day):
        next.day = day
        // Same as a tapped day, and for the same reason. The plus button is the other way to
        // say "add a batch here", so it has the same misclick profile as tapping the cell, and
        // treating it differently would mean the accident is unrecoverable through one door
        // and free through the other. Unnamed, staged, not merged: the first edit writes it.
        next.assembly = PCEventBatchAssembleUnitOfWork.new(anchor: day, using: provider)
        next.stage = .batchEditor
        next.scrollAnchor = day
        endingEventSelection(&next)
        requesting(&next, .presentBatchEditor)

    case let .openBatch(id):
        guard let batch = state.batches.first(where: { $0.mergeKey == id }) else { break }
        next.day = batch.date
        next.assembly = PCEventBatchAssembleUnitOfWork.existing(batch)
        next.stage = .batchEditor
        next.scrollAnchor = batch.date
        next.editorYear = nil
        // Every other action that stages an assembly re-projects the markers, and this one
        // was the exception. It happened to be invisible — opening a row projects the same
        // markers it already had — which is exactly why it survived: the invariant is
        // "the markers describe the batches plus whatever is staged", and holding it in one
        // place is cheaper than reasoning about which actions happen to satisfy it.
        endingEventSelection(&next)
        requesting(&next, .presentBatchEditor)

    // MARK: Stage transitions

    case .backTapped:
        switch state.stage {
        case .batchEditor:
            // Leaving the editor closes it. It does not undo: every edit merged into
            // `batches` as it was made, so the batch is already on the day and Back simply
            // reveals it. There is nothing staged here to discard — the assembly is the same
            // row, not a pending alternative to it — which is why this comment used to talk
            // about discarding a staged edit and no longer has anything to refer to.
            guard let assembly = state.assembly else { break }
            // Nothing survives the exit but the rows. A selection of `pendingID`s is scoped to
            // the assembly that is going away, and the stores are cached per calendar — so a
            // selection left behind would be waiting on the *next* batch this store stages,
            // describing events that are not its own.
            endingEventSelection(&next)
            // Whatever is staged joins the registry on the way out.
            //
            // In the real flow `editing` merged it the moment the edit was made and this is a
            // no-op that produces an identical array — which is why leaving writes nothing. It
            // is here so leaving cannot lose an edit that reached the assembly by any other
            // route, and because "the assembly holds something the registry does not describe"
            // is a state a fixture can build even though the reducer cannot reach it.
            //
            // **Except for a draft.** A batch staged by a tap or the plus button and left
            // unnamed has no edit behind it, so `editing` never merged it and this is the
            // only line that could — which would resurrect exactly the permanent misclick
            // that staging it unnamed was meant to prevent. Skipping the merge is the whole of
            // the discard, and it needs no delete: the row was never written, so there is
            // nothing in the database to remove.
            //
            // This is safe for a batch that *was* written and then had its name erased: it is
            // `isDraft` too, but `editing` already merged it, so skipping here changes
            // nothing and the row survives. The gate only ever suppresses a merge, never a
            // removal, which is why it cannot destroy user work.
            if let row = assembly.resolved(), assembly.canSave, !assembly.isDraft {
                next.batches = merging(row, into: state.batches, using: provider)
            }
            // An emptied batch is the one thing Back does have to decide, because it is the
            // delete. `resolved()` is `nil` for a batch with no events, and `editing` declines
            // to merge that — so the row is still in the registry, still in the database, and
            // still marking its days while the user looks at an editor with nothing in it.
            // Deleting on the last removal instead would be consistent with
            // persist-as-you-go, and it would also make a mis-tap on the final remaining day
            // destroy the batch outright, with no undo for a batch anywhere in the app.
            //
            // So the row survives until the user leaves, and leaving is the confirmation.
            // Waiting until then is also what makes the mis-tap recoverable: the day is
            // still in the batch, so tapping it again puts it back.
            if assembly.batch.isEmpty {
                next.batches = state.batches.filter { $0.mergeKey != assembly.mergeKey }
                next.assembly = nil
                next.stage = .idle
                next.day = nil
                next.didSave = true
                // To the root, not to the day's list: the batch that list would have shown is
                // the one just deleted, so the day list is now empty by construction. The
                // root route also clears `presentedSheet`, so the editor's sheet goes with it.
                requesting(&next, .popToCalendarRoot)
            } else if !next.batches.contains(where: { $0.mergeKey == assembly.mergeKey }) {
                // A draft that was never merged, so nothing was ever written for it. The tap
                // did not happen as far as the calendar is concerned, and leaving says so by
                // going back to the root rather than to the day's list — which would be empty,
                // and would show the user a day list for a batch they do not have.
                //
                // The second clause of `isDraft` alone cannot decide this. A batch that was
                // merged and *then* had its name erased is `isDraft` as well, and popping to
                // the root would hide a real batch from a day the user is still working on.
                // Presence in the registry is the thing that distinguishes "never written" from
                // "written and untitled", and it is the same fact the merge gate above acted
                // on.
                next.assembly = nil
                next.stage = .idle
                next.day = nil
                requesting(&next, .popToCalendarRoot)
            } else {
                next.assembly = nil
                // Re-anchor on the day the batch now lives, not the day it was opened on.
                //
                // `openBatch` set `day` to the row's first event, and an edit can remove
                // that very event — §16 removes three of four days — so popping to `next.day`
                // would land on a list the batch is no longer on, and the user would be shown
                // an empty day list after an edit that worked. `date` is derived from the
                // first event (§5.4), and every edit merged into `batches` as it was made, so
                // the registry is already the authority on where the batch belongs.
                //
                // The lookup cannot land on a day the batch is absent from: a row that is
                // here has at least one event, and that event is on `row.date`.
                let anchor = next.batches.first { $0.mergeKey == assembly.mergeKey }?.date ?? next.day
                next.day = anchor
                next.stage = next.day.map(PCEventSelectionStage.dayList) ?? .idle
                next.scrollAnchor = nil
                requesting(&next, .dismissBatchEditor)
            }
        case .dayList:
            next.stage = .idle
            next.day = nil
            next.assembly = nil
            requesting(&next, .pop)
        case .idle:
            break
        }

    case .closeTapped, .cancelTapped:
        next.stage = .idle
        next.day = nil
        next.assembly = nil
        endingEventSelection(&next)
        // Back to the committed markers: whatever was staged is gone.
        requesting(&next, .popToCalendarRoot)

    case .navigationRequestHandled:
        next.navigationRequest = nil

    // Declined, by design. "I finished typing that name" is a statement about *when*, and the
    // reducer is pure — it has no debounce to end. The keystrokes already merged the batch, so
    // there is genuinely nothing to change here; `PCEventSelectionManager` answers the action
    // by flushing the write it is holding.
    case .nameEditingFinished:
        break

    // MARK: Batch editor

    case let .setBatchName(name):
        // Staged in the assembly, merged into `batches`, but marked not-persisted: the store
        // holds the actual write back so consecutive keystrokes coalesce into one. See
        // `PCEventSelectionState.persistsAsTyped`.
        editing(state, &next, persistsAsTyped: true) { $0.renaming(name) }

    case let .setBatchColor(color):
        editing(state, &next) { $0.recoloring(color) }

    case let .toggleDay(day):
        guard state.stage == .batchEditor else { break }
        editing(state, &next) { $0.toggling(day: day, using: provider) }

    case let .removeEvent(pendingID):
        // A removed event leaves the selection too. Its id would otherwise linger, keeping
        // the picker enabled for a selection that resolves to nothing — so a pick would be
        // accepted and change no event at all.
        next.selectedEventIDs.remove(pendingID)
        editing(state, &next) { $0.removingEvent(pendingID: pendingID) }

    // MARK: Event selection in the batch editor

    case let .setEventSelectionMode(on):
        guard state.stage == .batchEditor else { break }
        next.isSelectingEvents = on
        if !on {
            next.selectedEventIDs = []
        }

    case let .toggleEventSelection(pendingID):
        guard state.stage == .batchEditor else { break }
        next.isSelectingEvents = true
        if next.selectedEventIDs.contains(pendingID) {
            next.selectedEventIDs.remove(pendingID)
        } else {
            next.selectedEventIDs.insert(pendingID)
        }

    case .selectAllEvents:
        guard state.stage == .batchEditor, let events = state.assembly?.batch.events else { break }
        next.isSelectingEvents = true
        next.selectedEventIDs = Set(events.map(\.pendingID))

    case .clearEventSelection:
        next.selectedEventIDs = []
        next.isSelectingEvents = false

    case let .applyTimeToSelectedEvents(time):
        guard state.stage == .batchEditor, !state.selectedEventIDs.isEmpty else { break }
        let ids = state.selectedEventIDs
        // One `editing`, so the whole selection lands in `batches` as a single change and the
        // store enqueues a single write. Folding the loop into the closure rather than
        // applying one action per event is what makes "picked 4 events, one write" hold —
        // four separate sends would coalesce into one write anyway, but only by accident of
        // the chain, and each would re-derive the markers.
        editing(state, &next) { assembly in
            var edited = assembly
            // Read the events off the assembly *as it stands* rather than off `state`, and
            // write each change straight back in: `applying` replaces by `pendingID`, so the
            // list can be walked in one pass without collecting first. The day comes from
            // the event and the clock from the picker, composed by the provider — which is
            // the only thing in the app that owns that arithmetic.
            for event in assembly.batch.events where ids.contains(event.pendingID) {
                guard let moved = provider.date(onDay: event.date, atTime: time) else { continue }
                edited = edited.applying(event.with(date: moved), using: provider)
            }
            return edited
        }
        // Not `persistsAsTyped`. This is one deliberate gesture, not typing, and a time the
        // user is still dragging through a wheel must not be held back by the name debounce
        // it has nothing to do with — that debounce coalesces keystrokes on one chain, and a
        // second writer on it is how a write order stops being the order the gestures were
        // made in.
        //
        // The selection is dropped afterwards, and that is the point of the whole gesture
        // rather than tidiness. The picker is enabled by having a selection, so leaving the
        // events ticked would leave it armed: the next box the user ticked — for whatever
        // reason, possibly to look at the row before deciding — would silently pick up the
        // time they had just set. Clearing it makes "pick a time for these events" a closed
        // action that ends by itself, and the picker greys out again to say so.
        next.selectedEventIDs = []
        next.isSelectingEvents = false

    // The event editor that used to be here had its own case per field — `openEvent`, `setEventName`,
    // `setEventDate`, `setEventColor`, `discardEventTapped` — and they all wrote the same value
    // twice: into `state.eventDraft`, and through `persistEventDraft` straight back into the
    // assembly the batch is built from. The draft existed only so the editor had something to
    // edit, so it went with the screen.

    case let .deleteBatches(list):
        let keys = Set(list.map(\.mergeKey))
        next.batches = state.batches.filter { !keys.contains($0.mergeKey) }
        // Nothing left on the day the user was looking at, so the day-list has nothing to
        // show and the stack unwinds to the calendar.
        if next.dayBatches.isEmpty {
            requesting(&next, .popToCalendarRoot)
        }

    case let .syncCalendar(calendarID, incoming):
        // The first sync establishes which calendar this store is about; a *different* one is
        // ignored. Guarding on equality alone would reject the very first sync, since
        // `calendarID` starts at 0.
        //
        // This guard was a data-loss bug wearing a defensive costume. `next.calendarID` is
        // assigned in exactly one place — here — so with one store for the whole process the
        // first calendar ever opened pinned the store for good: a second calendar's sync was
        // rejected, the registry kept the first calendar's rows, and every write still targeted
        // the pinned id, so a tap in the second calendar was written into the first
        // calendar's row by a destructive save. Nothing rejected the *sync* loudly; the second
        // calendar simply showed the first one's batches.
        //
        // The store is per calendar now (`PCAppSession.eventSelection(for:)`), so this can
        // only ever see one calendar and the branch is unreachable in production. It is kept
        // because it is the one place that would notice if a store were ever handed a second
        // calendar's rows, and silently accepting them would be worse than refusing.
        guard calendarID == state.calendarID || state.calendarID == 0 else { break }
        next.calendarID = calendarID
        // §6.5: a staged batch that came back from the store under a real id gets that id
        // adopted, so the next commit updates the row instead of appending a second one.
        // Resolved *before* the markers are projected, not after: adoption is what makes the
        // staged row recognisable as the incoming one, and a projection that ran first
        // would append the two copies of a row the user has just saved.
        //
        // **Both** assemblies are adopted, and that is the fix for "tapping four days made
        // four batches". This case used to adopt only `state.assembly` — the batch
        // *editor's* — so a multi-select session kept its `.pending(…)` key while the rows
        // around it were re-read under real ids. Every write in a session triggers a reload
        // (`CalendarCache.updateCalendar` re-fetches and broadcasts, `SingleCalendarModel`
        // answers with `syncCalendar`), so by the second tap the session's key answered to
        // nothing and `merging` appended instead of replacing: one batch per tap, each
        // holding the days accumulated so far. `state.assembly` is nil throughout a
        // multi-select session, which is why the session was invisible here and the
        // omission survived every test that exercised the editor path.
        next.assembly = adoptingPersistedID(
            for: state.assembly,
            in: incoming,
            registry: state.batches,
            using: provider
        )
        next.multiSelectAssembly = adoptingPersistedID(
            for: state.multiSelectAssembly,
            in: incoming,
            registry: state.batches,
            using: provider
        )
        // Adoption settles the session on *an* id. If a tap landed while the previous write
        // was still in flight, the database holds that earlier shape as its own row, and
        // nothing will ever carry it again — so it has to be dropped here, or it stays in
        // the registry for good and its days keep painting a second band.
        next.batches = withoutRowsOutgrown(
            by: state.multiSelectMode ? next.multiSelectAssembly : nil,
            in: incoming,
            knownIn: state.batches,
            using: provider
        )

    case .resetSession:
        next = PCEventSelectionState(dataProvider: provider)

    // MARK: Main calendar

    case let .setMultiSelectMode(on):
        next.multiSelectMode = on
        if !on {
            next.multiSelectDays = []
            next.multiSelectColor = nil
            // The scratchpad goes; the batch it wrote does not. Leaving the session is not
            // undoing the selection.
            next.multiSelectAssembly = nil
            // Leaving the session un-paints the days it had marked. Without this the days
            // stay marked until something else happens to rebuild the payload.
        }

    case let .setMultiSelectColor(color):
        next.multiSelectColor = color
        // Repaints a session that already has a batch. The days alone cannot reach here: a
        // tap needs a colour to be accepted at all, so a session that has days has had a
        // colour since the first of them, and the picker is disabled from that point
        // (`SingleCalendarModel.isColorPickerDisabled`). This used to double as the thing
        // that painted days chosen *before* a colour — which is how a session accumulated
        // four days and no batch, then coloured all four retroactively. It cannot happen
        // now, and the recolour below only has to cover changing a colour on a batch that
        // somehow exists without one.
        if let assembly = next.multiSelectAssembly, color != nil {
            next.multiSelectAssembly = assembly.recoloring(color)
        }

    case .confirmMultiSelectTapped:
        // The in-session exit: end the session and hand the batch to the **batch editor**.
        //
        // It used to end the session and stop, on the reasoning that "there is no review step
        // left, because the days were written as they were tapped". That was true while a tap
        // merged the row, and it stopped being true the moment an unnamed batch stopped being
        // written: the days are now a staged batch waiting for a name, and a checkmark that
        // threw that away was a worse affordance than one that asked for the name.
        //
        // So Confirm is now the door into the same editor a tapped day opens, and from there
        // the rules are the ones for creating a batch, unchanged: the first real edit merges
        // the row, and leaving an untouched draft unwinds to the calendar with nothing written.
        guard state.multiSelectMode else { break }
        endingMultiSelectSession(state, &next, presentingEditor: true)

    case .cancelMultiSelectTapped:
        // Leaving the session rather than just emptying it. §6.3 listed only the days and the
        // colour, which is incomplete: leaving `multiSelectMode` on would keep the multi-select
        // picker on screen after the user has cancelled it, and the view layer calls this when
        // leaving the calendar, expecting to land back in single selection.
        //
        // This is also what a calendar switch dispatches, which is why the deletion inside the
        // shared helper matters more on this path than anywhere else: the store is cached per
        // calendar, so a session that outlived its calendar would come back painted and
        // unendable the next time that calendar was opened.
        guard state.multiSelectMode else { break }
        endingMultiSelectSession(state, &next, stagingBatch: false, presentingEditor: false)

    case let .setNumberOfColumns(columns):
        next.numberOfColumns = columns

    case let .setEditorYear(year):
        next.editorYear = year

    case let .setScrollAnchor(anchor):
        next.scrollAnchor = anchor
    }

    // The marker payload is derived here, once, rather than recomputed by each case that
    // touches the assembly, the session or the registry.
    //
    // It used to be assigned in fourteen places, and that is exactly how the bug this
    // replaced got in: `dayTappedInCalendar` staged an assembly and never rebuilt the
    // payload, so the batch editor opened with the tapped day unmarked; `backTapped`
    // discarded the assembly and never rebuilt it either, so the marker outlived the edit
    // and the calendar claimed a day held an event that was never written. Each site was
    // individually reasonable — "this case changed the assembly, so refresh the markers" —
    // and the omission was invisible in review because the code next to it looks right.
    //
    // `dayEventColors` is not independent state. It is a pure function of `assembly`,
    // `multiSelectMode`, `multiSelectDays`, `multiSelectColor` and `batches`, all of which
    // are already settled by the time the switch ends. Deriving it in one place makes
    // "forgot to refresh the markers" unrepresentable, and a new case cannot reintroduce it.
    //
    // Which helper: the session's days are not a batch until the user confirms it, so a live
    // multi-select session has to be projected on top. Outside a session that overlay is
    // empty and this is just the committed batches with the staged assembly folded in.
    next.dayEventColors = next.derivedDayEventColors

    return next
}

// MARK: - Helpers

/// Records a navigation for the view layer. One more than whatever is pending, which
/// `navigationRequestHandled` resets — a pure reducer has no counter to persist.
private func requesting(_ state: inout PCEventSelectionState, _ target: NavigationRequest.Target) {
    state.navigationRequest = NavigationRequest(id: (state.navigationRequest?.id ?? 0) + 1, target: target)
}

/// Drops the batch editor's event selection and its selection mode.
///
/// One helper for every boundary the selection must not survive, because each of those
/// boundaries is a place where the ids in `selectedEventIDs` stop meaning what they meant.
/// They are `pendingID`s of an assembly: when the assembly goes (entering a batch, opening
/// one from the registry, leaving the editor, resetting the session) or when the user acts
/// on the rows as a list rather than as a set (leaving selection mode, clearing it),
/// carrying them forward would point a selection at events that are not in the batch being
/// edited. It would not fail loudly — `selectedEvents` filters against the current assembly
/// and quietly returns fewer or none — which is the reason this is one function rather than
/// a line repeated at each site: the sites are exactly where one of them gets missed.
///
/// `removeEvent` is deliberately *not* a boundary. It drops the single id it removed,
/// because the other ids in the selection are still perfectly good.
private func endingEventSelection(_ next: inout PCEventSelectionState) {
    next.isSelectingEvents = false
    next.selectedEventIDs = []
}

extension PCEventSelectionState {
    /// The marker payload this state implies: committed batches, the staged assembly folded
    /// in, and a live multi-select session projected on top.
    ///
    /// The session has no row, so it cannot come from `batches` or from the assembly; it is
    /// days plus a colour the user is assembling, and it is what the calendar must show
    /// while they do. With no colour chosen there is nothing to paint, so a session that has
    /// days but no colour is deliberately left unmarked rather than marked in a guess.
    ///
    /// ### Why this is on the state and not a free function in the reducer
    ///
    /// `dayEventColors` is a *derived* field that happens to be stored, because the store
    /// projects it into a year model the views bind to. The reducer derives it at its single
    /// exit, so a case cannot forget to refresh it — but that only holds for states the
    /// reducer produced. A test fixture that sets `assembly` by hand and leaves
    /// `dayEventColors` alone builds a state the reducer can never emit, and the first thing
    /// that surfaces is the rejected-action contract breaking: a guard that correctly
    /// changes nothing still "changes" the state, because the derivation disagrees with the
    /// hand-written payload.
    ///
    /// So the derivation is one function that fixtures call too. A fixture that cannot
    /// compute the payload cannot build an inconsistent state, which is the only way that
    /// class of fixture failure stays fixed.
    var derivedDayEventColors: [Date: [String]] {
        let session = multiSelectColor.map {
            (days: multiSelectDays, colorName: $0.colorName)
        }
        return PCCalendarMarkerProjector.colorsByDay(
            from: batches,
            includingStaged: assembly,
            multiSelect: multiSelectMode ? session : nil,
            using: dataProvider
        )
    }
}

/// Inserts `row`, replacing the entry with the same `mergeKey` if there is one.
// MARK: - Persisting as you go

/// Applies an edit to the staged assembly and writes the result through immediately.
///
/// The assembly is no longer where a change waits for Save — it is the scratchpad the edit
/// is expressed in, and the row it resolves to is merged into `batches` straight away. That
/// is the whole of "persist as you type": an edit is durable by the time the user has made
/// it, so there is never a Save-or-discard question to answer when they navigate away.
///
/// Merging keeps a single representation of the batch: `batches` is what the calendar
/// renders, and `assembly` is the same batch while it is being edited. Keeping them in step
/// here — rather than at Save — is what stops a half-built batch from living in only one of
/// them.
///
/// Returns without merging when the batch is not yet writable (no colour) or resolves to
/// nothing (no events). The first is not a save yet; the second is the delete path, where
/// `resolved()` is `nil` and the row should go rather than be written.
private func editing(
    _ state: PCEventSelectionState,
    _ next: inout PCEventSelectionState,
    persistsAsTyped: Bool = false,
    _ edit: (PCEventBatchAssembleUnitOfWork) -> PCEventBatchAssembleUnitOfWork
) {
    guard let assembly = state.assembly else { return }
    let edited = edit(assembly)
    next.assembly = edited
    guard edited.canSave, let row = edited.resolved() else { return }
    // Adopting by content, not just by key: this is where the debounced name write merges, and
    // it is the exact place the duplicate appeared — a write that has already landed can be
    // back in the registry under a real id while the assembly still holds the `.pending(…)`
    // one. See the content-adopting `merging` below for why that is now safe here.
    next.batches = merging(row, into: state.batches, using: state.dataProvider)
    // Sticky, not assigned. The debt a name edit creates is cleared by the **write**, which
    // happens in the store and not here, and this used to clear it itself — so a discrete edit
    // that produced an identical row (a colour already set to what it was, which is what
    // `commitNewBatch` does by naming a new batch and then setting its default colour) paid the
    // debt without writing anything. The typed name was then in the registry and nowhere else,
    // and the batch vanished on the next read.
    next.persistsAsTyped = next.persistsAsTyped || persistsAsTyped
}

/// `merging`, but a row the registry already describes **by content** is adopted rather than
/// duplicated.
///
/// This exists because of a race the key cannot survive. A staged batch is keyed
/// `pending(pendingID)` until a reload tells it the id the database gave its row, and adoption
/// on that reload is content-based. So if the write lands and the editor is left before that
/// reload arrives, the merge on the way out is keyed `pending(…)` while the registry already
/// holds the same batch as `persisted(7)` — two keys, one batch, and `merging` appends. The
/// symptom is one day listing the same batch twice, and it is intermittent because it depends
/// on the debounced write winning or losing a race with the Back tap.
///
/// Matching here is `hasSameContent`, not the looser `isSnapshot`: same name, same colour and
/// the **same days**. The loose one allows this row's days to be a subset of another's, and
/// that is what let a multi-select session adopt an unrelated untitled neighbour — see
/// `sessionReloadDoesNotTouchUnrelatedRows`. Requiring the identical day set is safe for the
/// case that matters: two batches the user cannot tell apart on a day list are one batch, and
/// the merge replaces the existing row (carrying its `persistedID`) instead of adding a
/// second.
///
/// Only the *merge* adopts. Nothing here deletes, so a false match costs an update and never
/// the user's work.
private func merging(
    _ row: CalendarEventBatch,
    into registry: [CalendarEventBatch],
    using dataProvider: PCCalendarDataProvider
) -> [CalendarEventBatch] {
    var out = registry
    if let index = out.firstIndex(where: { $0.mergeKey == row.mergeKey }) {
        out[index] = row
        return out
    }
    if let index = out.firstIndex(where: { $0.hasSameContent(as: row, using: dataProvider) }) {
        // Keep the id the store assigned: `row` is the staged value and carries a `.pending`
        // key, so merging it verbatim would write the batch back under a key that matches no
        // row on the next load.
        out[index] = row.with(persistedID: out[index].persistedID)
        return out
    }
    out.append(row)
    return out
}

// MARK: - Ending a multi-select session

/// Ends the live multi-select session, and deletes its batch if it ended up with no days.
///
/// One function for Confirm and Cancel because "ending a session" is one decision with one
/// consequence, and two copies of it is how they drift — which is how an emptied session came
/// to be confirmed into a staged, event-less batch while cancelling it left the row behind.
///
/// ## The deletion
///
/// A session whose days were all toggled back off has already had its row removed by the tap
/// that removed the last day, so this normally filters nothing. It is here anyway, at the
/// boundary where the session's life ends, because "the row is definitely already gone" is an
/// inference about a *previous* action — and this is the one place where no later action will
/// get a chance to clean up after it.
///
/// That matters more than it looks. The store is cached per calendar, so a session that outlived
/// its calendar came back painted and unendable on the next visit, and `withoutRowsOutgrown`
/// would drop that session's outgrown rows from the registry — after which the next tap's write,
/// being destructive, deletes them from the database for real. Ending the session on the way out
/// is what makes that helper's scope ("a live session") true.
///
/// ## The hand-off
///
/// `stagesBatch` is the only difference between the two callers. Confirm hands the batch on as
/// `state.assembly` and opens the editor on it, so a name given there reaches the same row the
/// taps were building; Cancel does not, because cancelling a session discards the *selection*
/// — the days were never written, so there is nothing to undo.
///
/// `presentingEditor` is navigation, and it is deliberately *not* implied by `stagesBatch`. A
/// calendar switch also ends sessions (`cancelMultiSelectTapped` is what it dispatches), and a
/// switch must never push a sheet over whatever the user was doing next.
///
/// The key is `assembly.mergeKey` and not `batch.mergeKey`: the adopted id lives outside the
/// batch, and a `.pending(…)` key matches no row in the registry at all.
private func endingMultiSelectSession(
    _ state: PCEventSelectionState,
    _ next: inout PCEventSelectionState,
    stagingBatch stagesBatch: Bool = true,
    presentingEditor presentsEditor: Bool = false
) {
    let session = next.multiSelectAssembly

    if let session {
        if session.batch.isEmpty {
            // Nothing was ever written for this session, so there is normally nothing to
            // remove here. The filter stays for the row a session *would* have left under the
            // old per-tap write, and for the boundary itself: "the row is definitely already
            // gone" is an inference about a previous action, and this is the last place that
            // could clean up after it.
            next.batches = state.batches.filter { $0.mergeKey != session.mergeKey }
        } else if stagesBatch {
            // Handed on **unwritten**, as the same `.new` assembly the taps built —
            // deliberately not `.existing`. Origin is what `isDraft` reads, and `isDraft` is
            // what makes Back discard an unnamed batch instead of writing it. Marking it
            // existing because "it was confirmed" would write a row nobody named, which is the
            // exact thing the name requirement exists to prevent.
            //
            // Not merged here either: the batch is unnamed, so `canSave` declines, and the
            // first edit inside the editor is what merges it. Everything downstream of Confirm
            // is then the ordinary batch-editor path, with no session left to special-case.
            next.assembly = session
            next.day = session.batch.date
            next.stage = .batchEditor
            if presentsEditor {
                requesting(&next, .presentBatchEditor)
            }
        }
    }

    next.multiSelectAssembly = nil
    next.multiSelectMode = false
    next.multiSelectDays = []
    next.multiSelectColor = nil
}

// MARK: - Adoption across a reload

/// The real id a staged batch's row came back under, if the reload recognised it.
///
/// Returns its input unchanged when there is nothing to adopt — no assembly, one that was
/// opened from the registry (its `persistedID` is already the answer), or one that has
/// already adopted. Matching is by content, because it is the only mechanism there is: a
/// DTO carries no `pendingID`, so `RootMapper` mints a fresh one for every row on every
/// load and a reloaded row's `mergeKey` can never equal a staged one's.
///
/// One helper for both assemblies, because the failure they shared was invisible for a
/// reason that only a shared implementation rules out. Adopting only the editor's meant a
/// multi-select session — where `state.assembly` is always `nil` — was silently skipped,
/// and the tests for this path asserted that the *editor* adopted, which was true.
private func adoptingPersistedID(
    for assembly: PCEventBatchAssembleUnitOfWork?,
    in incoming: [CalendarEventBatch],
    registry: [CalendarEventBatch],
    using provider: PCCalendarDataProvider
) -> PCEventBatchAssembleUnitOfWork? {
    guard
        let assembly,
        assembly.isNew,
        assembly.adoptedPersistedID == nil
    else {
        return assembly
    }

    // Two ways in, and the second is the one that survives a name still moving.
    //
    // The first is the heuristic this function has always had: the incoming row that could be
    // an earlier state of this batch, by `isSnapshot`. It fails while the user is typing,
    // because `isSnapshot` compares names exactly and a name that has advanced no longer looks
    // like the row that was written — and adoption is one-shot, so a single miss strands the
    // assembly on `.pending(…)` for good. Every later merge then looks for a key the registry
    // does not have, does not find it, and appends: one batch becomes two, and the stale one
    // keeps painting days the user has since removed from the live one.
    //
    // The second needs no heuristic to find the row. The registry row this assembly merged
    // into was `assembly.resolved()` — the same value, so it carries the assembly's
    // `pendingID`, and that is a link nothing else can forge: a reloaded row mints a fresh one
    // and no unrelated batch has ever held it. So `mine` is *known* to be this batch's row, and
    // the only question left is which incoming row is it — which `sameShape` answers without
    // looking at the name, because the name is the one field that legitimately differs between
    // two rows for the same batch while somebody is typing into it.
    //
    // Note what the second way is not allowed to do: match an incoming row against the
    // *assembly* on days alone. That is the loosening `merging` documents as having let a
    // session adopt an unrelated untitled neighbour. Here the `pendingID` has already answered
    // "which batch", so days and colour are only being used to say "which copy of it".
    let mine = registry.first { $0.pendingID == assembly.batch.pendingID }
    let candidate = incoming.first { $0.isSnapshot(of: assembly.batch, using: provider) }
        ?? mine.flatMap { row in incoming.first { sameShape($0, as: row, using: provider) } }

    guard let candidate, candidate.persistedID != nil else { return assembly }
    return assembly.adopting(persistedID: candidate.persistedID)
}

/// Whether `row` is the same batch as `mine`, **ignoring the name**.
///
/// Deliberately weaker than `isSnapshot`, and only ever used *after* a `pendingID` has already
/// identified `mine` as the row a staged assembly merged into. That is what makes the weakness
/// safe: `isSnapshot` has to guard against matching the wrong batch with its name and colour,
/// and this does not, because the batch is not in question — only which copy of it came back.
///
/// Days are compared as sets and the list is date-sorted by construction, so zip is a valid
/// pairing. Colour is exact: it is a decision the user made, and nothing drifts it.
private func sameShape(
    _ row: CalendarEventBatch,
    as mine: CalendarEventBatch,
    using provider: PCCalendarDataProvider
) -> Bool {
    guard
        row.colorName == mine.colorName,
        !row.events.isEmpty,
        row.events.count == mine.events.count
    else {
        return false
    }
    return zip(row.events, mine.events).allSatisfy { lhs, rhs in
        provider.isSameDay(lhs.date, rhs.date)
    }
}

/// The reload's rows, minus the ones a live session has already outgrown.
///
/// Scoped to a session for a reason that is not tidiness. Adoption picks *one* row for the
/// session to be row-id-wise; the writes that were in flight when the session grew past a
/// shape each left their own row behind, and `saveCalendar` is a destructive
/// read-modify-write, so those rows are in the database for as long as they are in the
/// incoming set. Applying this to the batch editor instead would delete rows the user is
/// actively editing, which is a much worse failure than the duplicate it fixes.
///
/// The `isSnapshot` test is what keeps it to the session's own history: same name, same
/// colour, and every day accounted for by the session. An unrelated batch that happens to
/// share a name and a colour but holds a day the session does not is untouched.
///
/// ## An emptied session, whose row has to be recognised by its absence
///
/// A session with no days left has had its row deleted, and its key is dead — `isSnapshot` has
/// nothing to compare, because the assembly is empty while the row a stale reload returns is the
/// *pre-deletion* snapshot, event and all. So a reload computed before the deleting write landed
/// can put the row back, and the session's key can never name it again.
///
/// Matching it by name and colour is the tempting fix and it is wrong: two untouched default
/// batches share both, so ending one session could delete the other's real work.
///
/// It does not have to be identified at all. While an emptied session is live, the session has
/// deleted exactly one row and created none since, so **a reloaded row the registry has never
/// seen can only be that row.** Every other row in `incoming` is already in `state.batches` —
/// a batch the user made before the session, or one the session made and then emptied — and is
/// left alone. Absence is the discriminator, and it cannot confuse two default batches because
/// both of those are present in the registry.
///
/// This was previously documented as self-healing, on the reasoning that `saveCalendar` deletes
/// everything absent from the incoming set. That was wrong: once the resurrected row is back in
/// `state.batches`, the next write *carries* it, so it is kept rather than deleted and the row
/// persists indefinitely.
private func withoutRowsOutgrown(
    by session: PCEventBatchAssembleUnitOfWork?,
    in incoming: [CalendarEventBatch],
    knownIn registry: [CalendarEventBatch],
    using provider: PCCalendarDataProvider
) -> [CalendarEventBatch] {
    guard let session else { return incoming }
    let settled = session.adoptedPersistedID ?? session.batch.persistedID

    guard !session.batch.isEmpty else {
        let known = Set(registry.compactMap(\.persistedID))
        return incoming.filter { row in
            guard row.persistedID != settled else { return false }
            // A row with no id did not come from the store, so it cannot be the resurrected one.
            guard let id = row.persistedID else { return true }
            return known.contains(id)
        }
    }

    return incoming.filter { row in
        row.persistedID == settled || !row.isSnapshot(of: session.batch, using: provider)
    }
}
