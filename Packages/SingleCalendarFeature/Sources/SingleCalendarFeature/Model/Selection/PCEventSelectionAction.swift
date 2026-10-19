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
    /// `removeEvent` still matches on `pendingID`, and that is right: its target lives inside
    /// the *staged assembly*, which is one value in state and is never rebuilt from a DTO, so
    /// the id is stable for as long as the edit lasts.
    case openBatch(id: EventBatchKey)
    /// "Turn this multi-select session into a batch" — and, since the session's batch is no
    /// longer written as the days are tapped, that means opening the batch editor on it.
    ///
    /// Nothing is declined here any more. It used to build the batch itself and was refused
    /// without a colour, and then it built nothing and simply ended the session, which left
    /// the user with a batch nobody had named and no place to name it. The colour is still
    /// what gates a *tap*, so a session that ends here has had one since its first day.
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

    /// "I have finished typing that name."
    ///
    /// Carries nothing and changes nothing, because the keystrokes already merged the batch into
    /// the registry. What they deliberately did **not** do is write it: every write publishes a
    /// cache change that comes back as a `syncCalendar`, and one landing mid-typing would roll
    /// the registry back to an older shape. So this is the action that ends the wait, and the
    /// store answers it by writing what the keystrokes merged.
    ///
    /// It fires from two places, and both are "typing is over": the field's Done key, and the
    /// field losing focus. Leaving the editor does the same thing without asking, so the one
    /// case this does not cover — a user who submits the field and then does not leave, switches
    /// apps, or sits looking at the batch they just named — is exactly the one it exists for.
    case nameEditingFinished

    /// The list selects rows rather than opening them — there is no event editor behind a row
    /// any more, so a tap on one means "include this" and nothing else. `false` also drops the
    /// selection: leaving selection mode and leaving a selection are one gesture, and keeping
    /// the ids would let the time picker apply to events the user can no longer see marked.
    case setEventSelectionMode(Bool)
    /// "Include this event in the selection."
    case toggleEventSelection(pendingID: UUID)
    case selectAllEvents
    case clearEventSelection
    /// "Give every selected event the time of day in `time`."
    ///
    /// This is now the *only* way a single event's own fields change: its name and colour come
    /// from `toggling` as a placeholder wearing the batch's colour, and there is no screen that
    /// edits either. Carrying the picked instant whole and letting the reducer extract the time
    /// of day through `PCCalendarDataProvider` keeps that arithmetic in one place — the
    /// alternative, carrying `(hour, minute)` as its own case, would make every caller decide
    /// how to name a time.
    ///
    /// An empty selection is declined rather than applied to the whole batch. "Apply to
    /// everything" is a real thing to want, but it is a different gesture from "apply to
    /// what I picked", and a picker that fires on every nudge of its wheel must never mean
    /// "everything" by default.
    case applyTimeToSelectedEvents(Date)

    // MARK: Persistence

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
