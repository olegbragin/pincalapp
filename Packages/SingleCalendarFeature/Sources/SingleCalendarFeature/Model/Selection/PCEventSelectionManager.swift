//
//  PCEventSelectionManager.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 29.09.2026.
//

import Foundation
import Observation
import CoreDomain
import DSKit

/// The store: the one place the batch-assembly state changes.
///
/// `PCEventSelectionState` is a value and `pcEventSelectionReducer` is a pure function, so
/// nothing about the transition is privileged — `send` is simply the only writer, and it
/// writes exactly what the reducer returned. There is no `didSet`, no property observer
/// and no second path in, which is the point: a store that can also be mutated directly
/// is a store with two sources of truth.
///
/// The store owns the three things the pure layer cannot. It projects `state` into the
/// year model the views render, it runs the effects the reducer derived, and it owns the
/// write queue that makes those effects land in order.
@MainActor
@Observable
public final class PCEventSelectionManager {
    /// The whole of the feature's state. Written only by `send`.
    public private(set) var state: PCEventSelectionState

    /// A calendar save that failed and has not been retried successfully, if any.
    ///
    /// `nil` means every write has landed. Its presence means the store's view of the calendar
    /// is **ahead of the database**, so the difference is real, unrecoverable user work — a
    /// save whose name or colour lives only in memory.
    ///
    /// This cannot be a log line. `saveCalendar` is read-modify-write with a destructive
    /// delete-then-insert, so a failed write does not merely fail to apply: the next successful
    /// write for the same calendar is computed from the store's state and overwrites the row,
    /// and anything the failed write was carrying is lost. Swallowing the error (`try?`) made
    /// that invisible, which is why this exists.
    public private(set) var failedSave: PCFailedSave?

    /// Re-attempts `failedSave`, keeping the store blocked until it succeeds.
    ///
    /// Retries the *failed payload*, not the current state: the point is to land the write that
    /// did not land. If the user has since typed more, that newer work is enqueued behind this
    /// one and will write afterwards.
    public func retryFailedSave() {
        guard let failure = failedSave else { return }
        enqueueWrite(
            calendarID: failure.calendarID,
            columns: failure.numberOfColumns,
            batches: failure.eventBatches
        )
    }

    /// Whether the calendar may be switched away right now.
    ///
    /// False only while a save has failed. In-flight writes are *not* a reason to block — the
    /// switch flushes them, and blocking on every keystroke-save would make the calendar feel
    /// sticky for no benefit.
    public var canSwitchCalendar: Bool {
        failedSave == nil
    }

    /// Settles in-flight work, then reports whether the calendar may be left.
    ///
    /// Two jobs, in this order, and the order is the point:
    ///
    /// 1. **Flush.** Awaits the chain so nothing is abandoned mid-switch. The session — and
    ///    with it this store — is torn down on switching calendars, so a write still in the
    ///    chain would simply stop existing, leaving the store's state ahead of the database.
    /// 2. **Refuse on failure.** Returns false if a write did not land, which cancels the
    ///    switch. The failure is already on screen with a Retry, and switching away would
    ///    destroy the store holding the payload needed to retry it.
    ///
    /// Returns true when there was nothing to do, so a calendar with no unsaved work switches
    /// as fast as it ever did.
    @discardableResult
    public func flushBeforeLeavingCalendar() async -> Bool {
        // Before the chain, because the chain is not the only thing that might hold a write:
        // a name typed in the last quarter-second is still waiting on the debounce and is not
        // in the chain at all. Flushing the chain alone would leave exactly the most recent
        // keystroke unsaved.
        nameAutosave.flush()
        await writeChain?.value

        // Nothing written, nothing lost: the common case, and it stays fast.
        if failedSave == nil {
            return true
        }

        // A write landed *after* the failure, for this same calendar. That write was computed
        // from the store's current state, which already includes everything the failed write
        // carried — so the failure is stale and there is nothing to retry. `enqueueWrite`
        // clears `failedSave` on exactly this case, so reaching here means the newest work
        // still did not land.
        return false
    }

    /// The batch editor's calendar. A *render target*, projected from `state` — not part of
    /// it. The day-model instances inside are the ones the views bind to, so this is
    /// mutated in place and rebuilt only when the year or the column count changes; see
    /// `projectCalendar`.
    ///
    /// Marked from `state.editorDayEventColors`, which is scoped to the batch being edited.
    /// This is not the main calendar's matrix and does not describe the calendar: see
    /// `PCEventSelectionState.editorDayEventColors` for why the two cannot share a payload.
    public private(set) var yearModel: PCCalendarYearModel

    /// Solves the `-UITestColumns` override. Carried through so the UI suite keeps its
    /// large, reliably tappable day cells.
    private let columnCountResolver: (Int) -> Int

    /// The data edge. A port, not a store: this file never names `CalendarCache`, so the
    /// feature layer stays free of `CorePersistence`.
    private let persistence: any CalendarPersisting

    /// The previous write's task. A write starts only after the one before it finished.
    ///
    /// The two `Task`s this replaces — `PCEventsSelectionManager.persistBatches` and
    /// `SingleCalendarModel.save(for:)` — both read-modify-wrote the same row with nothing
    /// ordering them, so a slow write could land after a fast one and silently drop a
    /// calendar update. Chaining is what makes "two concurrent writers" unrepresentable
    /// rather than merely unlikely.
    private var writeChain: Task<Void, Never>?

    /// Coalesces name edits. Typing is one edit, not one write per keystroke.
    ///
    /// Everything else — colours, days, creation — writes immediately, because those are
    /// discrete taps where there is nothing to coalesce and a user who taps and switches
    /// calendars expects the tap to be saved.
    private var nameAutosave: PCNameAutosave

    /// Presentational day selection for `yearModel`. Injected, not created here.
    ///
    /// `PCCalendarModelBuilder` needs a `PCCalendarDaySelectionManager` to wire the day
    /// cells, but the authoritative selection is `state.multiSelectDays`; this instance is
    /// a projection of it, rewritten by `projectCalendar`. So the manager is the *only*
    /// writer, which is why the year model can be wired to an object that arrives from
    /// outside and still stay in step.
    ///
    /// **The caller must pass an instance dedicated to this store.** It used to be created
    /// here, which made the exclusivity structural. Injected, it is a contract instead —
    /// and the one that matters is that this is *not* the main calendar's instance, because
    /// the store writes `selectedDays` on it and installs a tap listener on it. Share it
    /// and the editor's selection mode leaks onto the screen behind the sheet, and the
    /// main calendar's own listener fires on taps the editor thought were its own. That
    /// bug is why the old `PCEventsSelectionManager` took the main calendar's instance, and
    /// it is invisible in review because nothing about the signature is wrong. Hence the
    /// name: `daySelectionManager`, not `selectionManager`, and no default value — a
    /// defaulted dependency here would silently restore the old bug at every test site.
    private let daySelectionManager: PCCalendarDaySelectionManager

    public init(
        initialState: PCEventSelectionState = PCEventSelectionState(),
        persistence: any CalendarPersisting,
        daySelectionManager: PCCalendarDaySelectionManager,
        columnCountResolver: @escaping (Int) -> Int = { $0 },
        nameAutosaveDelay: Duration = PCNameAutosave.defaultDelay
    ) {
        // After every stored property is set: writing to `nameAutosave` first would touch
        // `self` before it is fully initialised.
        self.state = initialState
        self.columnCountResolver = columnCountResolver
        self.persistence = persistence
        self.daySelectionManager = daySelectionManager
        // Built with the caller's delay rather than assigned then adjusted: touching a
        // property before `yearModel` is set is using `self` before it is initialised.
        self.nameAutosave = PCNameAutosave(delay: nameAutosaveDelay)
        self.yearModel = PCCalendarModelBuilder.makeYearModel(
            from: initialState.dataProvider,
            year: initialState.editorYear,
            daySelectionManager: daySelectionManager,
            numberOfCurrentMonth: initialState.dataProvider.numberOfCurrentMonth,
            numberOfColumns: columnCountResolver(initialState.numberOfColumns),
            columnCountResolver: columnCountResolver
        )
    }

    // MARK: - The one mutation point

    /// Applies `action`, then projects and persists the result.
    ///
    /// The three steps are in this order deliberately. The state is committed before
    /// projection so the projection reads the state the views will read; projection happens
    /// before effects so a write is never issued against a year model that has not caught
    /// up; and the `next != previous` guard means a rejected action does not invalidate the
    /// year model at all.
    public func send(_ action: PCEventSelectionAction) {
        let previous = state
        let next = pcEventSelectionReducer(previous, action)
        if next != previous {
            state = next
        }

        projectCalendar()

        // Captured before the flag is cleared below, and only when the transition actually
        // took: a rejected action must not cancel or schedule anything.
        let nameEdit = next != previous && next.persistsAsTyped

        for effect in pcEventSelectionEffects(action, previous, next) {
            perform(effect, isNameEdit: nameEdit)
        }
    }

    // MARK: - Day taps in the editor's calendar

    /// Installs the single listener for a day tapped in the editor's calendar.
    ///
    /// The year model the editor binds to is wired to the store's own
    /// `PCCalendarDaySelectionManager`, so the store is the only thing that can install a
    /// listener on it. Exactly one screen listens at a time: the batch editor while it is
    /// visible, nothing otherwise.
    ///
    /// This replaces watching `selectedDays` with `onChange` and inferring intent from
    /// its contents. A set used as a message bus cannot tell "the user tapped a day" from
    /// "a day was seeded into the set", which is exactly why the editor had to clear the
    /// set defensively on every stage, and why the main calendar could flash the
    /// multi-select picker when staging a batch changed the mode underneath it.
    public func installDayTapHandler(_ handler: @escaping @MainActor (Date) -> Void) {
        daySelectionManager.onDayTapped = handler
    }

    /// Removes the listener.
    ///
    /// Not optional housekeeping: the handler captures the store, so leaving it installed
    /// past the screen's lifetime breaks the one-listener-at-a-time invariant.
    public func clearDayTapHandler() {
        daySelectionManager.onDayTapped = nil
    }

    // MARK: - Projection

    /// Brings `yearModel` in line with `state`.
    ///
    /// Rebuilt only when the year or the resolved column count changes; otherwise the day
    /// models are mutated in place. A rebuild per action would hand the views fresh
    /// `PCCalendarDayModel` instances, and the views bind to the ones they were given, so
    /// the calendar would stop updating after the first action — the reason
    /// `PCCalendarYearModel.months` stores the matrix instead of computing it.
    private func projectCalendar() {
        let dataProvider = state.dataProvider
        let resolvedYear = state.editorYear ?? dataProvider.currentYear
        let resolvedColumns = columnCountResolver(state.numberOfColumns)

        if yearModel.months.isEmpty
            || yearModel.year != resolvedYear
            || yearModel.numberOfColumns != resolvedColumns
        {
            yearModel = PCCalendarModelBuilder.makeYearModel(
                from: dataProvider,
                year: state.editorYear,
                daySelectionManager: daySelectionManager,
                numberOfCurrentMonth: dataProvider.numberOfCurrentMonth,
                numberOfColumns: state.numberOfColumns,
                columnCountResolver: columnCountResolver
            )
        }

        // The editor's calendar, so the editor's payload: this matrix exists to pick days
        // for the batch being edited, and every other batch's days are wrong there rather
        // than merely redundant. `SingleCalendarModel` projects the calendar-wide
        // `state.dayEventColors` into the *main* matrix, which is the panel that is
        // supposed to describe every batch.
        PCCalendarMarkerProjector.apply(state.editorDayEventColors, to: yearModel, using: dataProvider)
        yearModel.scrollTargetMonth = state.scrollAnchor.map { dataProvider.month(of: $0) }
        daySelectionManager.selectedDays = Set(state.multiSelectDays)
    }

    // MARK: - Effects

    /// Runs one effect.
    ///
    /// `id == 0` is not a calendar: the session opens with no calendar selected, and a
    /// write against that would either fail or land on an arbitrary row. The reducer can
    /// emit such an effect for a session that has not been given a calendar yet, so the
    /// guard belongs here, next to the call that would do the damage.
    private func perform(_ effect: PCEventSelectionEffect, isNameEdit: Bool = false) {
        guard
            case let .writeCalendar(id, columns, batches) = effect,
            id != 0
        else { return }

        // The reducer marks name edits rather than writing them, because debouncing is a
        // function of time and the reducer is pure. Here — where effects run — the timing
        // finally applies: the write is scheduled instead of issued, and the flag is cleared
        // so a later edit schedules a fresh one rather than being swallowed by this one.
        if isNameEdit {
            nameAutosave.change { [weak self] in
                guard let self else { return }
                self.enqueueWrite(calendarID: id, columns: columns, batches: batches)
            }
            return
        }

        // A colour, day or creation write supersedes any pending name write for the same
        // calendar: it carries the same batches with the name already folded in, so waiting
        // for the debounce would write a row that is known to be stale.
        nameAutosave.cancel()

        enqueueWrite(calendarID: id, columns: columns, batches: batches)
    }

    /// Appends one write to the chain, recording it if it fails.
    ///
    /// The chain is what makes "two concurrent writers" unrepresentable: each write awaits its
    /// predecessor, so a slow write cannot land after a fast one. What it does not do is
    /// report failure — so the failure is captured here, against the payload that failed,
    /// which is what `retryFailedSave` needs and what makes the loss recoverable.
    private func enqueueWrite(calendarID: Int64, columns: Int, batches: [CalendarEventBatch]) {
        let previous = writeChain
        writeChain = Task { [persistence] in
            await previous?.value
            do {
                try await persistence.save(
                    numberOfColumns: columns,
                    eventBatches: batches,
                    forCalendar: calendarID
                )
                // Cleared only on success, and only for a failure this write supersedes. A
                // newer failure must not be erased by an older write landing afterwards.
                if failedSave?.calendarID == calendarID {
                    failedSave = nil
                }
            } catch {
                failedSave = PCFailedSave(
                    calendarID: calendarID,
                    numberOfColumns: columns,
                    eventBatches: batches,
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            }
        }
    }
}
