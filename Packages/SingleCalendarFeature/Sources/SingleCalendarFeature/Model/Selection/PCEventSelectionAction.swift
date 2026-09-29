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
    case openBatch(pendingID: UUID)
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
