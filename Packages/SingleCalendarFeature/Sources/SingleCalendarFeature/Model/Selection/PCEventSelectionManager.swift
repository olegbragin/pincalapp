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

    /// The batch editor's calendar. A *render target*, projected from `state` — not part of
    /// it. The day-model instances inside are the ones the views bind to, so this is
    /// mutated in place and rebuilt only when the year or the column count changes; see
    /// `projectCalendar`.
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
        columnCountResolver: @escaping (Int) -> Int = { $0 }
    ) {
        self.state = initialState
        self.columnCountResolver = columnCountResolver
        self.persistence = persistence
        self.daySelectionManager = daySelectionManager
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
        if next != previous { state = next }

        projectCalendar()

        for effect in pcEventSelectionEffects(action, previous, next) {
            perform(effect)
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

        PCCalendarMarkerProjector.apply(state.dayEventColors, to: yearModel, using: dataProvider)
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
    private func perform(_ effect: PCEventSelectionEffect) {
        guard
            case .writeCalendar(let id, let columns, let batches) = effect,
            id != 0
        else { return }

        let previous = writeChain
        writeChain = Task { [persistence] in
            await previous?.value
            try? await persistence.save(
                numberOfColumns: columns,
                eventBatches: batches,
                forCalendar: id
            )
        }
    }
}
