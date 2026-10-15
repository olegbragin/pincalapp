//
//  PCEventSelectionAction.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 28.09.2026.
//

import Foundation
import CoreDomain
import DSKit

/// Everything that can happen to the assembly line.
///
/// An action is a *statement of intent*, not a command: it says what the user did, and the
/// reducer decides what that means. A view never assigns state and never asks what a
/// change did — it sends, and reads the result.
public enum PCEventSelectionAction: Equatable {
    // MARK: Entry

    /// "Make sure the line is ready." A no-op by design — the reducer has nothing to
    /// prepare, because there is no lazy construction left to do — but it gives a view a
    /// safe thing to send on appearing, and a redundant send changes nothing.
    case ensureAssemblyStarted
    case dayTappedInCalendar(Date)
    case startNewBatch(on: Date)
    /// "Open this batch for editing."
    ///
    /// Carries the row's `mergeKey`, not its `pendingID`. `pendingID` is *session*
    /// identity and is not durable: a DTO carries none, so every row is re-minted with a
    /// fresh `UUID` on every load, and `SingleCalendarModel` re-syncs on every calendar
    /// write. Matching on it meant that a card tapped after any intervening reload named
    /// a row that no longer existed — the lookup failed, the action was rejected, and the
    /// tap did nothing at all, with no error anywhere to explain it.
    ///
    /// `mergeKey` is `.persisted(id)` for a committed row, and a reload cannot change it.
    /// It falls back to `.pending(_)` only for a batch that has never been written, which
    /// is the one case where there is no durable identity to offer.
    ///
    /// `openEvent` and `removeEvent` still match on `pendingID`, and that is right: their
    /// targets live inside the *staged assembly*, which is one value in state and is never
    /// rebuilt from a DTO, so their ids are stable for as long as the edit lasts.
    case openBatch(id: EventBatchKey)
    /// "Turn this multi-select session into a batch." Needs a colour to build the batch
    /// with, so the reducer declines while `multiSelectColor` is `nil`. It was deferred to
    /// Stage 7 along with the colour itself.
    case confirmMultiSelectTapped

    // MARK: Stage transitions

    case backTapped
    case closeTapped
    case cancelTapped
    /// The view layer says it has carried out the pending request. Without this the same
    /// request would sit in state forever, and the next one could not be distinguished
    /// from it.
    case navigationRequestHandled

    // MARK: Batch editor

    case setBatchName(String)
    case setBatchColor(PCColorOption?)
    case toggleDay(Date)
    case removeEvent(pendingID: UUID)

    /// The event list is selecting rather than opening. `false` also drops the selection —
    /// leaving selection mode and leaving a selection are one gesture, and keeping the ids
    /// would let the time picker apply to events the user can no longer see marked.
    case setEventSelectionMode(Bool)
    /// "Include this event in the selection."
    case toggleEventSelection(pendingID: UUID)
    case selectAllEvents
    case clearEventSelection
    /// "Give every selected event the time of day in `time`."
    ///
    /// Carries the picked instant whole, as the event editor's `setEventDate` does, and lets
    /// the reducer extract the time of day from it through `PCCalendarDataProvider`. The
    /// alternative — carrying `(hour, minute)` as its own case — would make every caller
    /// decide how to name a time, which is the arithmetic the provider exists to own.
    ///
    /// An empty selection is declined rather than applied to the whole batch. "Apply to
    /// everything" is a real thing to want, but it is a different gesture from "apply to
    /// what I picked", and a picker that fires on every nudge of its wheel must never mean
    /// "everything" by default.
    case applyTimeToSelectedEvents(Date)

    // MARK: Event editor

    case openEvent(pendingID: UUID)
    case setEventName(String)
    case setEventDate(Date)
    case setEventColor(PCColorOption?)

    // MARK: Persistence

    case discardEventTapped
    case deleteBatches([CalendarEventBatch])

    // MARK: Main calendar

    case setMultiSelectMode(Bool)
    case setMultiSelectColor(PCColorOption?)
    case cancelMultiSelectTapped
    case setNumberOfColumns(Int)
    case setEditorYear(Int)
    case setScrollAnchor(Date?)

    // MARK: External sync

    case syncCalendar(calendarID: Int64, batches: [CalendarEventBatch])
    case resetSession
}
