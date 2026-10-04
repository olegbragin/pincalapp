//
//  PCEventBatchAssembleUnitOfWork.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 28.09.2026.
//

import Foundation
import CoreDomain
import DSKit

/// The unit of work on the assembly line: a batch being edited, plus where it came from.
///
/// A pure value. No store, no clock, no I/O, and every transformation returns a new
/// instance rather than mutating — which is what makes the whole edit/merge/resolve path
/// testable without a view, a repository, or an actor.
///
/// It exists to hold identity in one place. Today that job is spread across three
/// mechanisms in `PCEventsSelectionManager` — `BatchMergeKey`, the
/// `persistedIDsByPendingTimestamp` table, and `contentEquals` — and they disagree with
/// each other. Here it is one `mergeKey` on the value and one `resolved(against:)`, and
/// the duplicate-batch bug in §16 cannot be expressed.
///
/// It is `Sendable` so it can sit in state that a pure reducer compares. `DSKit` is
/// already a dependency of this package, and `PCColorOption` is the only reason the type
/// is not in `CoreDomain`.
public struct PCEventBatchAssembleUnitOfWork: Equatable, Sendable {
    public private(set) var batch: CalendarEventBatch

    /// Where this assembly entered the line. `.new` was started by the user;
    /// `.existing` was opened from a row already in the registry.
    public private(set) var origin: Origin

    /// Set when a reload revealed this assembly's batch already exists in the store
    /// under a different id, so a later commit updates that row instead of appending a
    /// duplicate. Set by the `syncCalendar` adoption in §6.5, applied by
    /// `resolved(against:)`.
    public var adoptedPersistedID: Int64?

    public enum Origin: Equatable, Sendable {
        case new
        case existing(pendingID: UUID)
    }

    public var isNew: Bool {
        origin == .new
    }

    /// The key this assembly's row answers to, *including* an id it has adopted.
    ///
    /// Not the same as `batch.mergeKey`. An assembly opened from the registry already
    /// carries the row's `persistedID`, so the two agree. An assembly that was *new* when
    /// it was staged only learns its id from `adopting(persistedID:)` during a reload, and
    /// until it does its `pendingID` can never equal the `.persisted(_)` key of the row
    /// that came back for it. Anything that has to recognise the staged row as the same
    /// one the registry holds — the marker projection above all — has to ask this rather
    /// than `batch.mergeKey`, or it appends a second copy of a row it already has.
    public var mergeKey: EventBatchKey {
        adoptedPersistedID.map(EventBatchKey.persisted) ?? batch.mergeKey
    }

    /// Whether this batch is in a state worth writing.
    ///
    /// A batch needs a **colour** to be written, and nothing else. The name is not required,
    /// because the name is not what makes a batch a batch: a batch is a set of dated, coloured
    /// events, and a user who taps a day and leaves the title alone has still made a real
    /// batch that they expect to be there when they come back.
    ///
    /// Requiring a name used to mean that expectation was not met. The check was described as
    /// preventing "a freshly-tapped day from being committed as a row of blank events", but
    /// colour was already required, so the only batches it stopped were the ones a user
    /// intended: named-by-default batches, renamed-to-empty ones. And because edits persist as
    /// they are made, refusing to save did not leave the work staged and recoverable — it left
    /// the store ahead of the database with nowhere to put it.
    ///
    /// What it gates now is only whether `editing` merges a row. It no longer has a button:
    /// there is no Save in either editor, so "the user cannot save this yet" has no way to be
    /// expressed to them, and a batch that exists without a colour exists only mid-edit — the
    /// editor, having opened on `PCColorOption.firstAvailable`, always has one.
    ///
    /// `resolved()` still returns `nil` for a batch with no events, so it is the `editing`
    /// helper's `let row =` guard, not this flag, that keeps an eventless row from being
    /// persisted. That still matters for the delete path: removing every event empties the
    /// batch, and leaving the editor deletes the row. Folding `!events.isEmpty` in here
    /// instead would make that unreachable — declined from exactly the state that triggers the
    /// delete, and the row would sit in the calendar marking days the user had just cleared.
    public var canSave: Bool {
        !batch.colorName.isEmpty
    }

    private init(batch: CalendarEventBatch, origin: Origin) {
        self.batch = batch
        self.origin = origin
    }

    // MARK: - Identity

    /// A brand-new batch holding one day, arriving ready to save.
    ///
    /// Named and coloured by default. This used to produce an *unnamed, uncoloured* batch,
    /// which combined with `canSave` to make a freshly-tapped day a dead end: the editor
    /// opened on a grey picker and an empty field, Save was disabled, and the user had to
    /// find both controls before the batch could be committed at all. Defaults mean the
    /// common case — tap a day, notice the mistake, undo it — needs no edits, and a batch
    /// the user does want is savable straight away.
    ///
    /// Both parameters still take arguments, for the tests that assert the uncoloured and
    /// unnamed shapes, but the defaults are what production callers get.
    ///
    /// The anchor is normalised to the start of its day, so a freshly created event sits at
    /// midnight until the user gives it a time. It has to be a whole day rather than
    /// whatever instant the tap carried, because every later comparison — `occurs(on:using:)`,
    /// `hasSameContent(as:using:)`, the day-marker projection — keys on the *day*, and one that
    /// compared instants would disagree with itself about which day a batch is on.
    ///
    /// Only creation normalises. `applying` deliberately does not: it takes the event's date
    /// verbatim so a time the user picked survives.
    public static func new(
        anchor: Date,
        name: String = PCEventBatchAssembleUnitOfWork.defaultBatchName,
        colorName: String = PCColorOption.firstAvailable.colorName,
        using dataProvider: PCCalendarDataProvider
    ) -> PCEventBatchAssembleUnitOfWork {
        let day = dataProvider.startOfDay(for: anchor)
        let batch = CalendarEventBatch(
            name: name,
            colorName: colorName,
            events: [placeholder(on: day, colorName: colorName)]
        )
        return PCEventBatchAssembleUnitOfWork(batch: batch, origin: .new)
    }

    /// A brand-new batch holding one placeholder per selected day, for the multi-select
    /// path. `days` are sorted, so the result does not depend on the order they were
    /// tapped in.
    public static func new(
        all days: [Date],
        color: PCColorOption?,
        using dataProvider: PCCalendarDataProvider
    ) -> PCEventBatchAssembleUnitOfWork {
        // A nil colour is *not* a reason to build an unsavable batch. The multi-select
        // path can only reach here through the reducer, which refuses to confirm without a
        // colour, so the nil is defensive — and defaulting keeps the two entry points to
        // "a new batch" agreeing about what one looks like.
        let colorName = color?.colorName ?? PCColorOption.firstAvailable.colorName
        let events = days
            .map { placeholder(on: dataProvider.startOfDay(for: $0), colorName: colorName) }
            .sorted { $0.date < $1.date }
        let batch = CalendarEventBatch(
            name: PCEventBatchAssembleUnitOfWork.defaultBatchName,
            colorName: colorName,
            events: events
        )
        return PCEventBatchAssembleUnitOfWork(batch: batch, origin: .new)
    }

    /// Opens a batch already in the registry for editing. Its `pendingID` is recorded so
    /// the commit can find the row again by `mergeKey`.
    public static func existing(_ batch: CalendarEventBatch) -> PCEventBatchAssembleUnitOfWork {
        PCEventBatchAssembleUnitOfWork(batch: batch, origin: .existing(pendingID: batch.pendingID))
    }

    // MARK: - Transformations

    public func renaming(_ name: String) -> PCEventBatchAssembleUnitOfWork {
        var copy = self
        copy.batch = batch.with(name: name)
        return copy
    }

    /// Recolours the batch and every event in it.
    ///
    /// Events are updated unconditionally, including when the colour is cleared.
    /// `CalendarEventBatch.with(colorName:propagateToEvents:)` deliberately skips
    /// propagation for an empty name, which is right for a partially-typed batch but
    /// wrong here: the day markers are projected from *event* colours, so a batch
    /// recoloured to nothing while its events kept the old colour would keep painting
    /// markers for a colour the batch no longer has.
    public func recoloring(_ color: PCColorOption?) -> PCEventBatchAssembleUnitOfWork {
        let colorName = color?.colorName ?? ""
        var copy = self
        copy.batch = batch
            .with(colorName: colorName)
            .with(events: batch.events.map { $0.with(colorName: colorName) })
        return copy
    }

    /// Turns a day on if it is off, off if it is on.
    ///
    /// The removal runs first and unconditionally. That is what makes "a day never holds
    /// two events" true by construction rather than by argument: whatever was on the day
    /// is gone before anything is added, so no input can produce a second event there.
    /// The append is then conditional — if the removal took something, this was a toggle
    /// *off* and we stop.
    public func toggling(day: Date, using dataProvider: PCCalendarDataProvider) -> PCEventBatchAssembleUnitOfWork {
        let target = dataProvider.startOfDay(for: day)
        let remaining = batch.events.filter { !dataProvider.isSameDay($0.date, target) }
        var copy = self
        if remaining.count == batch.events.count {
            // Nothing was on the day, so this turns it on.
            copy.batch = batch.with(events: remaining + [Self.placeholder(on: target, colorName: batch.colorName)])
        } else {
            copy.batch = batch.with(events: remaining)
        }
        return copy
    }

    public func removingEvent(pendingID: UUID) -> PCEventBatchAssembleUnitOfWork {
        let remaining = batch.events.filter { $0.pendingID != pendingID }
        guard remaining.count != batch.events.count else { return self }
        var copy = self
        copy.batch = batch.with(events: remaining)
        return copy
    }

    /// Folds an edited event back into the batch.
    ///
    /// One expression covers both cases, because both questions have the same answer.
    /// An event is replaced when it is already in the batch *by* `pendingID`, and a day
    /// is vacated when the incoming event lands on one that already holds an event. So
    /// the surviving events are those that are neither the same event nor on the
    /// incoming event's day, and the incoming event is appended. That is what makes
    /// moving an event onto an occupied day a move rather than a duplicate — and it
    /// holds even when the edit changes an existing event's date onto a taken day, which
    /// the pendingID-only rule would let through.
    public func applying(_ event: CalendarEvent, using dataProvider: PCCalendarDataProvider) -> PCEventBatchAssembleUnitOfWork {
        // The incoming date is taken as it comes, time component and all. It used to be
        // normalised to the start of its day here, which threw away the time the user had
        // just picked in the event editor: the binding carried it, the draft carried it, and
        // this line dropped it on the way into the batch. So the batch went on listing the
        // event at 12:00 AM, reopening the event showed the picker back at midnight, and the
        // only symptom was that "the time is not saved".
        //
        // The normalisation was solving the right problem in the wrong place. What actually
        // needs to be day-granular is *identity* — which event occupies which day — and that
        // is the survivor test below, which has always compared days and never instants.
        // Truncating the stored value bought nothing the comparison was not already
        // guaranteeing, and cost the time of day.
        let incoming = event
        let survivors = batch.events.filter {
            $0.pendingID != incoming.pendingID && !dataProvider.isSameDay($0.date, incoming.date)
        }
        var copy = self
        copy.batch = batch.with(events: survivors + [incoming])
        return copy
    }

    public func adopting(persistedID: Int64?) -> PCEventBatchAssembleUnitOfWork {
        var copy = self
        copy.adoptedPersistedID = persistedID
        return copy
    }

    /// The row to write, or `nil` when the batch has been emptied and the calendar's
    /// row must go instead.
    ///
    /// This is the single home of the duplicate-batch logic, replacing the old
    /// `BatchMergeKey` / `persistedIDsByPendingTimestamp` / `contentEquals` trio. The id
    /// is `adoptedPersistedID ?? batch.persistedID`, and §5.4's original
    /// `resolved(against: batches)` — which looked the row up in the registry by
    /// `mergeKey` — was removed as unreachable. The proof is short: if some row `r`
    /// matches `batch.mergeKey`, then
    ///
    /// - when `batch.persistedID` is non-nil the key is `.persisted(id)`, so
    ///   `r.persistedID == batch.persistedID`, and
    /// - when it is nil the key is `.pending(uuid)`, which never equals
    ///   `.persisted(_)`, so `r.persistedID` is nil as well.
    ///
    /// Either way the lookup returned exactly what the batch already carried. Identity
    /// has two real sources and no third: an explicit reassignment from a reload, which
    /// only `adoptedPersistedID` knows, and the id the batch was opened with. Matching a
    /// batch across a reload by *content* is §6.5's job, and it is the only mechanism
    /// that can — a DTO carries no `pendingID`, so the mapper mints a fresh one per row
    /// per load and a reloaded row's key can never equal a staged one's.
    public func resolved() -> CalendarEventBatch? {
        guard !batch.isEmpty else { return nil }
        return batch.with(persistedID: adoptedPersistedID ?? batch.persistedID)
    }

    // MARK: - Placeholder

    /// An event occupying a day, named by default.
    ///
    /// It used to be empty, and the empty name is what a "has this been named?" guard read
    /// as *unedited*. That made the guard useless in practice: a placeholder could never be
    /// saved and every one of them had to be typed out first, and a batch whose events were
    /// never opened could not be committed at all. The guard still means "has a name" — it
    /// just no longer rejects a value that is already there.
    ///
    /// Midnight, deliberately. A day that has just been switched on has no time yet, and the
    /// event editor is where a time is chosen; midnight is the honest "unset" rather than a
    /// fabricated default like 09:00 that the user then has to notice and correct.
    private static func placeholder(on day: Date, colorName: String) -> CalendarEvent {
        CalendarEvent(name: defaultEventName, date: day, colorName: colorName)
    }

    // MARK: Defaults

    //
    // Display strings, in a domain type, which is the one layering compromise here and is
    // worth naming rather than hiding: a new batch's *name* has to be born somewhere, and
    // the alternatives are worse. The view cannot supply it — the name is store state, and
    // pre-filling a text field that is bound to it would fight the binding on the first
    // keystroke. A factory taking a name would push the default up to every call site and
    // they would drift.
    //
    // So they live here, in English, and are *not* localised. A localised default needs the
    // generated string table, and the batch name is the user's own text once they touch it —
    // it is a starting point, not chrome. If a translated default is ever wanted, the
    // honest place is a `BatchNaming` port injected alongside `dataProvider`, and this
    // constant becomes its English fallback.

    /// What a new batch is called before the user says otherwise.
    public static let defaultBatchName = "New event"

    /// What a new event inside a batch is called.
    public static let defaultEventName = "New event day"
}
