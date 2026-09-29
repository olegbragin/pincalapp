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
            // The marker payload does not move: it is projected from `batches` plus the
            // staged assembly, and neither contains a multi-select day until the session
            // is confirmed — which is deferred to Stage 7 along with the colour that
            // would give a marker anything to paint.
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
            // Uncoloured on purpose. A day that was merely tapped has no name and no
            // colour yet, so `canSave` is false and `saveTapped` will refuse it until the
            // user fills both in.
            next.assembly = BatchAssembler.new(anchor: day, colorName: "", using: provider)
            next.stage = .batchEditor
            next.scrollAnchor = day
            next.editorYear = nil
            next.isDirty = true
            requesting(&next, .pushBatchEditor)
        }

    case .startNewBatch(on: let day):
        next.day = day
        next.assembly = BatchAssembler.new(anchor: day, colorName: "", using: provider)
        next.stage = .batchEditor
        next.scrollAnchor = day
        next.isDirty = true
        requesting(&next, .pushBatchEditor)

    case .openBatch(let pendingID):
        guard let batch = state.batches.first(where: { $0.pendingID == pendingID }) else { break }
        next.day = batch.date
        next.assembly = BatchAssembler.existing(batch)
        next.stage = .batchEditor
        next.scrollAnchor = batch.date
        next.editorYear = nil
        next.isDirty = true
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
        next.isDirty = false
        // Back to the committed markers: whatever was staged is gone.
        next.dayEventColors = PCCalendarMarkerProjector.colorsByDay(from: state.batches, using: provider)
        requesting(&next, .popToCalendarRoot)

    case .navigationRequestHandled:
        next.navigationRequest = nil

    // MARK: Batch editor

    case .setBatchName(let name):
        guard let assembly = state.assembly else { break }
        next.assembly = assembly.renaming(name)
        next.isDirty = true

    case .setBatchColor(let color):
        guard let assembly = state.assembly else { break }
        next.assembly = assembly.recoloring(color)
        next.dayEventColors = markers(for: next)
        next.isDirty = true

    case .toggleDay(let day):
        guard state.stage == .batchEditor, let assembly = state.assembly else { break }
        next.assembly = assembly.toggling(day: day, using: provider)
        next.dayEventColors = markers(for: next)
        next.isDirty = true

    case .removeEvent(let pendingID):
        guard let assembly = state.assembly else { break }
        next.assembly = assembly.removingEvent(pendingID: pendingID)
        next.dayEventColors = markers(for: next)
        next.isDirty = true

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
        next.isDirty = true

    case .setEventDate(let date):
        guard let draft = state.eventDraft else { break }
        next.eventDraft = draft.with(date: date)
        next.isDirty = true

    case .setEventColor(let color):
        guard let draft = state.eventDraft else { break }
        next.eventDraft = draft.with(colorName: color?.colorName ?? "")
        next.isDirty = true

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
        next.dayEventColors = markers(for: next)
        next.isDirty = true
        requesting(&next, .pop)

    case .discardEventTapped:
        next.eventDraft = nil
        next.stage = .batchEditor
        requesting(&next, .pop)

    // MARK: Persistence

    case .commitTapped:
        guard let assembly = state.assembly, assembly.canSave, let row = assembly.resolved() else { break }
        next.batches = merging(row, into: state.batches)
        next.isDirty = true

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
                next.stage = next.day.map(PCEventSelectionStage.dayList) ?? .idle
                next.didSave = true
                next.isDirty = false
                requesting(&next, .pop)
            } else {
                // The batch was emptied, so its row has to leave the calendar. Note this
                // branch does not require `canSave`: there is nothing left to be valid.
                next.batches = state.batches.filter { $0.mergeKey != assembly.batch.mergeKey }
                next.assembly = nil
                next.stage = .idle
                next.didSave = true
                next.isDirty = false
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
            next.isDirty = false
            requesting(&next, .pop)

        case .idle:
            break
        }

    case .deleteBatches(let list):
        let keys = Set(list.map(\.mergeKey))
        next.batches = state.batches.filter { !keys.contains($0.mergeKey) }
        next.isDirty = true
        next.dayEventColors = PCCalendarMarkerProjector.colorsByDay(from: next.batches, using: provider)
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
        next.isDirty = false
        next.dayEventColors = PCCalendarMarkerProjector.colorsByDay(
            from: incoming,
            includingStaged: state.assembly,
            using: provider
        )
        // §6.5: a staged batch that came back from the store under a real id gets that id
        // adopted, so the next commit updates the row instead of appending a second one.
        if
            let assembly = state.assembly,
            assembly.isNew,
            assembly.adoptedPersistedID == nil,
            let match = incoming.first(where: {
                $0.persistedID != nil && $0.hasSameContent(as: assembly.batch, using: provider)
            })
        {
            next.assembly = assembly.adopting(persistedID: match.persistedID)
        }

    case .resetSession:
        next = PCEventSelectionState(dataProvider: provider)

    // MARK: Main calendar

    case .setMultiSelectMode(let on):
        next.multiSelectMode = on
        if !on {
            next.multiSelectDays = []
            next.multiSelectColor = nil
        }

    case .setMultiSelectColor(let color):
        next.multiSelectColor = color

    case .confirmMultiSelectTapped:
        // An assembly cannot be built without a colour to build it with, and there is
        // nothing to confirm without days. Either way the session is left exactly as it
        // was — a rejected action never half-builds a batch.
        guard state.multiSelectMode, !state.multiSelectDays.isEmpty, let color = state.multiSelectColor
        else { break }
        let anchor = state.multiSelectDays.min() ?? state.day
        next.assembly = BatchAssembler.new(all: state.multiSelectDays, color: color, using: provider)
        next.day = anchor
        next.stage = .batchEditor
        next.scrollAnchor = anchor
        next.isDirty = true
        // The session has become a batch; leaving `multiSelectMode` on would keep the
        // calendar behind the editor presenting itself as mid-selection.
        next.multiSelectMode = false
        next.multiSelectDays = []
        next.multiSelectColor = nil
        next.dayEventColors = PCCalendarMarkerProjector.colorsByDay(
            from: state.batches,
            includingStaged: next.assembly,
            using: provider
        )
        requesting(&next, .pushBatchEditor)

    case .cancelMultiSelectTapped:
        next.multiSelectDays = []
        next.multiSelectColor = nil
        next.dayEventColors = PCCalendarMarkerProjector.colorsByDay(from: state.batches, using: provider)

    case .setNumberOfColumns(let columns):
        next.numberOfColumns = columns
        next.isDirty = true

    case .setEditorYear(let year):
        next.editorYear = year

    case .setScrollAnchor(let anchor):
        next.scrollAnchor = anchor
    }

    return next
}

// MARK: - Helpers

/// Records a navigation for the view layer. One more than whatever is pending, which
/// `navigationRequestHandled` resets — a pure reducer has no counter to persist.
private func requesting(_ state: inout PCEventSelectionState, _ target: NavigationRequest.Target) {
    state.navigationRequest = NavigationRequest(id: (state.navigationRequest?.id ?? 0) + 1, target: target)
}

/// The marker payload for a state: committed batches plus whatever is staged.
private func markers(for state: PCEventSelectionState) -> [Date: [String]] {
    PCCalendarMarkerProjector.colorsByDay(
        from: state.batches,
        includingStaged: state.assembly,
        using: state.dataProvider
    )
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
