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

    case .dayTappedInCalendar(let day):
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
            // Written as it changes, so Save has nothing left to commit — it only ends the
            // session.
            //
            // The merge is against `state.batches` rather than `next.batches` so a tap can
            // only ever change this session's row. Merging against `next` would let the
            // day-list mutation above leak in, and the two disagree whenever a day is
            // toggled off.
            if let row = assembly.resolved() {
                next.batches = merging(row, into: state.batches)
            } else {
                // Every day has been toggled back off, so the session's row leaves the
                // calendar with them. `resolved()` is `nil` for an empty batch and `merging`
                // has no case for that. The batch editor's answer is `backTapped`, which
                // deletes an emptied batch as it leaves; a session has no Back button and no
                // Save, so the write has to happen here. The key is `assembly.mergeKey` and
                // not `assembly.batch.mergeKey`, because the adopted id lives outside the
                // batch and a `.pending(…)` key matches no row in the registry at all.
                next.batches = state.batches.filter { $0.mergeKey != assembly.mergeKey }
            }
        } else if state.batches.contains(where: { $0.occurs(on: day, using: provider) }) {
            next.day = day
            next.stage = .dayList(day: day)
            next.assembly = nil
            requesting(&next, .pushDayList)
        } else {
            next.day = day
            // Named and coloured by default (§5.4), so a merely-tapped day is already
            // savable. It used to be staged deliberately uncoloured, on the reasoning that
            // `canSave` would refuse to commit it until the user filled both in — which
            // also meant the editor opened with Save disabled, and the only way out of an
            // accidental tap was to type a name and pick a colour before backing out.
            next.assembly = PCEventBatchAssembleUnitOfWork.new(anchor: day, using: provider)
            // Written on creation, not on Save. Tapping a day is a decision to add a batch,
            // and it is a decision that already has everything needed to write one: a day
            // and the default colour. Making the user confirm it again meant the batch could
            // be abandoned by navigating away, which is the save-or-discard question this
            // feature no longer has.
            next.batches = merging(
                next.assembly!.resolved()!,
                into: state.batches
            )
            next.stage = .batchEditor
            next.scrollAnchor = day
            next.editorYear = nil
            requesting(&next, .pushBatchEditor)
        }

    case .startNewBatch(on: let day):
        next.day = day
        next.assembly = PCEventBatchAssembleUnitOfWork.new(anchor: day, using: provider)
        // Same as a tapped day: the plus button already carries the day the batch list is
        // scoped to, so the batch is fully determined and is written immediately.
        next.batches = merging(
            next.assembly!.resolved()!,
            into: state.batches
        )
        next.stage = .batchEditor
        next.scrollAnchor = day
        requesting(&next, .pushBatchEditor)

    case .openBatch(let id):
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
        requesting(&next, .pushBatchEditor)


    // MARK: Stage transitions

    case .backTapped:
        switch state.stage {
        case .eventEditor:
            // Leaving the event editor drops the draft and nothing else. Every field of it
            // was already written into the assembly as it was typed (`persistEventDraft`), so
            // the draft is a working copy rather than the pending change — discarding it
            // loses nothing.
            //
            // This is what `saveEventTapped` used to do after additionally re-applying the
            // draft, which was redundant for the same reason, and the checkmark that sent it
            // is gone. `discardEventTapped` said the identical thing and had no button
            // either: two actions for one gesture, which is how a redundant one survives.
            next.eventDraft = nil
            next.stage = .batchEditor
            requesting(&next, .pop)
        case .batchEditor:
            // Leaving the editor closes it. It does not undo: every edit merged into
            // `batches` as it was made, so the batch is already on the day and Back simply
            // reveals it. There is nothing staged here to discard — the assembly is the same
            // row, not a pending alternative to it — which is why this comment used to talk
            // about discarding a staged edit and no longer has anything to refer to.
            guard let assembly = state.assembly else { break }
            // Whatever is staged joins the registry on the way out.
            //
            // In the real flow `editing` merged it the moment the edit was made and this is a
            // no-op that produces an identical array — which is why leaving writes nothing. It
            // is here so leaving cannot lose an edit that reached the assembly by any other
            // route, and because "the assembly holds something the registry does not describe"
            // is a state a fixture can build even though the reducer cannot reach it.
            if let row = assembly.resolved(), assembly.canSave {
                next.batches = merging(row, into: state.batches)
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
                // the one just deleted, so the day list is now empty by construction.
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
                requesting(&next, .pop)
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
        next.eventDraft = nil
        // Back to the committed markers: whatever was staged is gone.
        requesting(&next, .popToCalendarRoot)

    case .navigationRequestHandled:
        next.navigationRequest = nil

    // MARK: Batch editor

    case .setBatchName(let name):
        // Staged in the assembly, merged into `batches`, but marked not-persisted: the store
        // holds the actual write back so consecutive keystrokes coalesce into one. See
        // `PCEventSelectionState.persistsAsTyped`.
        editing(state, &next, persistsAsTyped: true) { $0.renaming(name) }

    case .setBatchColor(let color):
        editing(state, &next) { $0.recoloring(color) }

    case .toggleDay(let day):
        guard state.stage == .batchEditor else { break }
        editing(state, &next) { $0.toggling(day: day, using: provider) }

    case .removeEvent(let pendingID):
        editing(state, &next) { $0.removingEvent(pendingID: pendingID) }

    // MARK: Event editor

    case .openEvent(let pendingID):
        guard
            let assembly = state.assembly,
            let event = assembly.batch.events.first(where: { $0.pendingID == pendingID })
        else { break }
        next.eventDraft = event
        next.stage = .eventEditor(
            batchPendingID: assembly.batch.pendingID,
            eventPendingID: event.pendingID
        )
        requesting(&next, .pushEventEditor)

    case .setEventName(let name):
        guard let draft = state.eventDraft else { break }
        next.eventDraft = draft.with(name: name)
        // Debounced for the same reason as `setBatchName`: typing is one edit, not five
        // writes.
        persistEventDraft(state, &next, draft.with(name: name), persistsAsTyped: true)

    case .setEventDate(let date):
        guard let draft = state.eventDraft else { break }
        next.eventDraft = draft.with(date: date)
        persistEventDraft(state, &next, draft.with(date: date))

    case .setEventColor(let color):
        guard let draft = state.eventDraft else { break }
        let edited = draft.with(colorName: color?.colorName ?? "")
        next.eventDraft = edited
        persistEventDraft(state, &next, edited)

    case .discardEventTapped:
        next.eventDraft = nil
        next.stage = .batchEditor
        requesting(&next, .pop)

    case .deleteBatches(let list):
        let keys = Set(list.map(\.mergeKey))
        next.batches = state.batches.filter { !keys.contains($0.mergeKey) }
        // Nothing left on the day the user was looking at, so the day-list has nothing to
        // show and the stack unwinds to the calendar.
        if next.dayBatches.isEmpty {
            requesting(&next, .popToCalendarRoot)
        }

    case .syncCalendar(let calendarID, let incoming):
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
        // The store is per calendar now (`PCCalendarSession.eventSelection(for:)`), so this can
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
        next.assembly = adoptingPersistedID(for: state.assembly, in: incoming, using: provider)
        next.multiSelectAssembly = adoptingPersistedID(for: state.multiSelectAssembly, in: incoming, using: provider)
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

    case .setMultiSelectMode(let on):
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

    case .setMultiSelectColor(let color):
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
            let recoloured = assembly.recoloring(color)
            next.multiSelectAssembly = recoloured
            if let row = recoloured.resolved() {
                next.batches = merging(row, into: state.batches)
            }
        }

    case .confirmMultiSelectTapped:
        // The in-session exit: end the session and, unlike Cancel, hand the batch on as the
        // staged assembly. Nothing is pushed — there is no review step left, because the days
        // were written as they were tapped.
        guard state.multiSelectMode else { break }
        endingMultiSelectSession(state, &next)

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
        endingMultiSelectSession(state, &next, stagingBatch: false)

    case .setNumberOfColumns(let columns):
        next.numberOfColumns = columns

    case .setEditorYear(let year):
        next.editorYear = year

    case .setScrollAnchor(let anchor):
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
    next.batches = merging(row, into: state.batches)
    next.persistsAsTyped = persistsAsTyped
}

/// Folds an edited event draft back into its batch and writes the batch through.
///
/// Separate from `editing` because the event editor's work lives in `eventDraft` rather than
/// in the assembly — the draft is a copy, and the batch only learns about it here. Without
/// this the event's name, date and colour would keep the Save/discard shape while its parent
/// batch's had lost it.
private func persistEventDraft(
    _ state: PCEventSelectionState,
    _ next: inout PCEventSelectionState,
    _ draft: CalendarEvent,
    persistsAsTyped: Bool = false
) {
    guard let assembly = state.assembly else { return }
    let updated = assembly.applying(draft, using: state.dataProvider)
    next.assembly = updated
    guard updated.canSave, let row = updated.resolved() else { return }
    next.batches = merging(row, into: state.batches)
    next.persistsAsTyped = persistsAsTyped
}

private func merging(
    _ row: CalendarEventBatch,
    into registry: [CalendarEventBatch]
) -> [CalendarEventBatch] {
    var out = registry
    if let index = out.firstIndex(where: { $0.mergeKey == row.mergeKey }) {
        out[index] = row
    } else {
        out.append(row)
    }
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
/// `state.assembly` so a staged edit survives; Cancel does not, because cancelling a session
/// discards the *scratchpad*, not the row — the days were written as they were tapped, so there
/// is nothing to undo.
///
/// The key is `assembly.mergeKey` and not `batch.mergeKey`: the adopted id lives outside the
/// batch, and a `.pending(…)` key matches no row in the registry at all.
private func endingMultiSelectSession(
    _ state: PCEventSelectionState,
    _ next: inout PCEventSelectionState,
    stagingBatch stagesBatch: Bool = true
) {
    let session = next.multiSelectAssembly

    if let session {
        if session.batch.isEmpty {
            next.batches = state.batches.filter { $0.mergeKey != session.mergeKey }
        } else if stagesBatch, let row = session.resolved() {
            // Normally already identical to the registry row — every tap merged it — so this
            // writes nothing. Merged rather than trusted so that leaving cannot lose a batch
            // that reached the assembly by any other route.
            next.batches = merging(row, into: state.batches)
            next.assembly = session
            next.day = row.date
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
    using provider: PCCalendarDataProvider
) -> PCEventBatchAssembleUnitOfWork? {
    guard
        let assembly,
        assembly.isNew,
        assembly.adoptedPersistedID == nil,
        let match = incoming.first(where: {
            $0.persistedID != nil && $0.isSnapshot(of: assembly.batch, using: provider)
        })
    else {
        return assembly
    }
    return assembly.adopting(persistedID: match.persistedID)
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
