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
            // Normalise the tap before comparing: what is stored is a start-of-day, and
            // comparing a start-of-day against a raw instant invites the two to disagree
            // about which day they name.
            let target = provider.startOfDay(for: day)
            if next.multiSelectDays.contains(where: { provider.isSameDay($0, target) }) {
                next.multiSelectDays.removeAll { provider.isSameDay($0, target) }
            } else {
                next.multiSelectDays.append(target)
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
            next.stage = .batchEditor
            next.scrollAnchor = day
            next.editorYear = nil
            requesting(&next, .pushBatchEditor)
        }

    case .startNewBatch(on: let day):
        next.day = day
        next.assembly = PCEventBatchAssembleUnitOfWork.new(anchor: day, using: provider)
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
            next.eventDraft = nil
            next.stage = .batchEditor
            requesting(&next, .pop)
        case .batchEditor:
            // Backing out of the editor discards the staged edit — that is the difference
            // between this and `saveTapped`. The committed batches for the day are still
            // there to come back to.
            next.assembly = nil
            next.stage = next.day.map(PCEventSelectionStage.dayList) ?? .idle
            requesting(&next, .pop)
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
        guard let assembly = state.assembly else { break }
        next.assembly = assembly.renaming(name)

    case .setBatchColor(let color):
        guard let assembly = state.assembly else { break }
        next.assembly = assembly.recoloring(color)

    case .toggleDay(let day):
        guard state.stage == .batchEditor, let assembly = state.assembly else { break }
        next.assembly = assembly.toggling(day: day, using: provider)

    case .removeEvent(let pendingID):
        guard let assembly = state.assembly else { break }
        next.assembly = assembly.removingEvent(pendingID: pendingID)

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

    case .setEventDate(let date):
        guard let draft = state.eventDraft else { break }
        next.eventDraft = draft.with(date: date)

    case .setEventColor(let color):
        guard let draft = state.eventDraft else { break }
        next.eventDraft = draft.with(colorName: color?.colorName ?? "")

    case .saveEventTapped:
        // An unnamed event is not a save, it is a dismissal — rejecting it leaves the
        // editor open and the draft intact rather than silently dropping the edits.
        guard
            let draft = state.eventDraft,
            !draft.name.isEmpty,
            let assembly = state.assembly
        else { break }
        next.assembly = assembly.applying(draft, using: provider)
        next.eventDraft = nil
        next.stage = .batchEditor
        requesting(&next, .pop)

    case .discardEventTapped:
        next.eventDraft = nil
        next.stage = .batchEditor
        requesting(&next, .pop)

    // MARK: Persistence

    case .commitTapped:
        guard let assembly = state.assembly, assembly.canSave, let row = assembly.resolved() else { break }
        next.batches = merging(row, into: state.batches)

    case .saveTapped:
        switch state.stage {
        case .dayList:
            next.stage = .idle
            next.day = nil
            requesting(&next, .popToCalendarRoot)

        case .batchEditor:
            guard let assembly = state.assembly else { break }
            if let row = assembly.resolved() {
                guard assembly.canSave else { break }
                next.batches = merging(row, into: state.batches)
                next.assembly = nil
                // Re-anchor the session on the day the batch now lives, not the day it was
                // opened on.
                //
                // `openBatch` set `day` to the row's first event, and an edit can remove
                // that very event — §16 removes three days and leaves the fourth, so the
                // saved row is listed on a day the session is no longer pointing at. The
                // pop then returns to that day's list, which is empty because the batch is
                // not on it, and the user is shown an empty list after a save that
                // succeeded. `date` is derived from the first event (§5.4), so the saved
                // row is the authority on where it belongs.
                //
                // This also cannot land on a day the batch is absent from: `resolved()`
                // returns `nil` for an empty batch, so a row that gets here has at least
                // one event, and that event is on `row.date` by construction.
                next.day = row.date
                next.stage = next.day.map(PCEventSelectionStage.dayList) ?? .idle
                next.scrollAnchor = nil
                next.didSave = true
                // The row's events are the markers now, and the assembly that was
                // projecting them is gone. Recomputing rather than leaving the staged
                // payload behind is what keeps "the markers describe the batches plus
                // whatever is staged" true at the end of the edit as well as during it.
                requesting(&next, .pop)
            } else {
                // The batch was emptied, so its row has to leave the calendar. This is the
                // delete: the user removed every event and pressed Save. `canSave` is not
                // consulted here, and no longer excludes the empty case either — an emptied
                // batch is named and coloured, so it reaches this branch rather than being
                // stranded behind a disabled button.
                next.batches = state.batches.filter { $0.mergeKey != assembly.batch.mergeKey }
                next.assembly = nil
                next.stage = .idle
                next.didSave = true
                // The row is gone from the calendar, so its days have to stop being marked.
                // While the batch was staged this was already true — the staged copy
                // replaced its committed row in the projection — but the registry has just
                // changed underneath it, and the markers are stated in terms of the
                // registry.
                requesting(&next, .popToCalendarRoot)
            }

        case .eventEditor:
            guard var assembly = state.assembly, assembly.canSave else { break }
            if let draft = state.eventDraft {
                assembly = assembly.applying(draft, using: provider)
            }
            if let row = assembly.resolved() {
                next.batches = merging(row, into: state.batches)
            }
            next.eventDraft = nil
            next.assembly = nil
            next.stage = next.day.map(PCEventSelectionStage.dayList) ?? .idle
            next.didSave = true
            requesting(&next, .pop)

        case .idle:
            break
        }

    case .deleteBatches(let list):
        let keys = Set(list.map(\.mergeKey))
        next.batches = state.batches.filter { !keys.contains($0.mergeKey) }
        // Nothing left on the day the user was looking at, so the day-list has nothing to
        // show and the stack unwinds to the calendar.
        if next.dayBatches.isEmpty {
            requesting(&next, .popToCalendarRoot)
        }

    case .syncCalendar(let calendarID, let incoming):
        // The first sync establishes which calendar the session is about; later syncs for
        // a *different* calendar are ignored. Guarding on equality alone would reject the
        // very first sync, since `calendarID` starts at 0.
        guard calendarID == state.calendarID || state.calendarID == 0 else { break }
        next.calendarID = calendarID
        next.batches = incoming
        // §6.5: a staged batch that came back from the store under a real id gets that id
        // adopted, so the next commit updates the row instead of appending a second one.
        // Resolved *before* the markers are projected, not after: adoption is what makes the
        // staged row recognisable as the incoming one, and a projection that ran first
        // would append the two copies of a row the user has just saved.
        var staged = state.assembly
        if
            let assembly = staged,
            assembly.isNew,
            assembly.adoptedPersistedID == nil,
            let match = incoming.first(where: {
                $0.persistedID != nil && $0.hasSameContent(as: assembly.batch, using: provider)
            })
        {
            staged = assembly.adopting(persistedID: match.persistedID)
            next.assembly = staged
        }
    case .resetSession:
        next = PCEventSelectionState(dataProvider: provider)

    // MARK: Main calendar

    case .setMultiSelectMode(let on):
        next.multiSelectMode = on
        if !on {
            next.multiSelectDays = []
            next.multiSelectColor = nil
            // Leaving the session un-paints the days it had marked. Without this the days
            // stay marked until something else happens to rebuild the payload.
        }

    case .setMultiSelectColor(let color):
        next.multiSelectColor = color
        // Days chosen before the colour still have to be painted in it, or the calendar
        // would sit there unmarked until the next tap.

    case .confirmMultiSelectTapped:
        // An assembly cannot be built without a colour to build it with, and there is
        // nothing to confirm without days. Either way the session is left exactly as it
        // was — a rejected action never half-builds a batch.
        guard state.multiSelectMode, !state.multiSelectDays.isEmpty, let color = state.multiSelectColor
        else { break }
        let anchor = state.multiSelectDays.min() ?? state.day
        next.assembly = PCEventBatchAssembleUnitOfWork.new(all: state.multiSelectDays, color: color, using: provider)
        next.day = anchor
        next.stage = .batchEditor
        next.scrollAnchor = anchor
        // The session has become a batch; leaving `multiSelectMode` on would keep the
        // calendar behind the editor presenting itself as mid-selection.
        next.multiSelectMode = false
        next.multiSelectDays = []
        next.multiSelectColor = nil
        requesting(&next, .pushBatchEditor)

    case .cancelMultiSelectTapped:
        // Exits the session, not just empties it. §6.3 listed only the days and the
        // colour, which is incomplete: leaving `multiSelectMode` on would keep the
        // multi-select picker on screen after the user has cancelled it, and the view
        // layer calls this when leaving the calendar, expecting to land back in single
        // selection.
        next.multiSelectMode = false
        next.multiSelectDays = []
        next.multiSelectColor = nil

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
