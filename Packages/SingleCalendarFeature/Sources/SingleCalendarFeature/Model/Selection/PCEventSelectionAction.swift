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

    // MARK: Event editor

    case openEvent(pendingID: UUID)
    case setEventName(String)
    case setEventDate(Date)
    case setEventColor(PCColorOption?)

    // MARK: Persistence

    case commitTapped
    case saveTapped
    case saveEventTapped
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
