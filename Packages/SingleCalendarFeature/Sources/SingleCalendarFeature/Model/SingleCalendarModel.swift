//
//  SingleCalendarModel.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 04.02.2026.
//

import Foundation
import Observation
import SwiftUI
import AppNavigation
import CoreDomain
import DSKit

/// The main calendar panel.
///
/// This keeps two things the store deliberately does not: the *main* year matrix, and the
/// main calendar's day-selection manager. The store owns the batch-assembly line and the
/// editor's calendar; this owns the panel the user is looking at when they are choosing
/// days, and reads everything else from the store.
///
/// What it lost is the batch half. It used to hold `addedEvents`, `selectedColor`,
/// `originalBatches`, stage a placeholder event, build an `EventBatchDataSource` and
/// return an `AppRoute` — a second implementation of the assembly line, with its own
/// notion of what a day tap means and its own idea of what to persist. All of that is
/// `PCEventSelectionState` now, and this model dispatches instead of deciding.
///
/// No `CorePersistence` either, and that is deliberate. This model used to hold a
/// `CalendarCache` for one thing only — the calendar's own metadata change feed, i.e.
/// its name, year, archived flag and column count. That is not batch state, so it never
/// belonged to the batch port, and it is not storage either, so it does not belong to
/// the feature importing the storage vocabulary. It is calendar *management*, which is
/// what `CalendarManaging` is for: the reads go through
/// `CalendarPersisting.calendar(id:)`, the feed through `CalendarManaging.changes()`.
/// Both are domain ports, and the package is off `CorePersistence` for good.
@MainActor
@Observable
public final class SingleCalendarModel {
    public enum State {
        case empty
        case content
        case loading
    }

    /// The calendar's metadata change feed, as a port.
    ///
    /// The model follows the calendar's own name, year, archived flag and column count, and
    /// none of those are batch state. They arrive through `CalendarManaging` rather than
    /// the cache so this file can stop naming the storage vocabulary; the feed is a *new*
    /// stream per call, which is why the loop below is the only thing that may hold one.
    private let managing: any CalendarManaging

    /// The port the batch graph is read through. `cache.getCalendar` hands back
    /// `[EventBatchDataSource]` — a persistence DTO — and mapping it is the composition
    /// root's job, not this model's. Asking the port for the batches is what keeps the
    /// DTO inside `CorePersistence`.
    private let persistence: any CalendarPersisting
    private let dataProvider: PCCalendarDataProvider
    private let store: PCEventSelectionManager

    public private(set) var calendarid: Int64
    public private(set) var label: String = ""
    public private(set) var isArchived: Bool = false

    /// The main panel's year matrix. Distinct from `store.yearModel`, which is the
    /// *editor's* calendar — two panels, two matrices, one projection function.
    public private(set) var yearModel: PCCalendarYearModel

    /// The main calendar's own selection manager. Separate from the store's because it
    /// belongs to this panel; the store's belongs to the batch editor.
    public let daySelectionManager: PCCalendarDaySelectionManager

    /// The year the matrix was last built for from the persisted calendar. The view may
    /// switch the displayed year without touching this, so a later fetch doesn't undo the
    /// user's choice.
    private var builtCalendarYear: Int?

    public var state: State = .empty

    /// The calendar's own change feed. Ends when the model deallocates: the loop's
    /// `guard let self` breaks, which terminates the task and releases the stream.
    @ObservationIgnored private var changesTask: Task<Void, Never>?

    private let columnCountResolver: (Int) -> Int

    public init(
        calendarid: Int64,
        managing: any CalendarManaging,
        persistence: any CalendarPersisting,
        store: PCEventSelectionManager,
        dataProvider: PCCalendarDataProvider = PCCalendarDataProvider(),
        daySelectionManager: PCCalendarDaySelectionManager = PCCalendarDaySelectionManager(),
        columnCountResolver: @escaping (Int) -> Int = { $0 }
    ) {
        self.calendarid = calendarid
        self.managing = managing
        self.persistence = persistence
        self.store = store
        self.dataProvider = dataProvider
        self.daySelectionManager = daySelectionManager
        self.columnCountResolver = columnCountResolver
        self.yearModel = PCCalendarModelBuilder.makeYearModel(
            from: dataProvider,
            year: nil,
            daySelectionManager: daySelectionManager,
            numberOfCurrentMonth: dataProvider.numberOfCurrentMonth,
            numberOfColumns: 3,
            columnCountResolver: columnCountResolver
        )
        self.builtCalendarYear = yearModel.year
        changesTask = Task { [weak self] in
            for await change in await managing.changes() {
                guard let self else { return }
                if Self.touchedIDs(in: change).contains(calendarid) {
                    // Keeps the subscription alive on a failed refetch.
                    //
                    // The alternative — letting `fetch` throw — would end this loop on the first
                    // database hiccup, and a change feed has no replay: every later write from
                    // any other screen would be missed for the rest of this calendar's life.
                    // Continuing is therefore strictly better than propagating, even though it
                    // is not yet *reported*; reporting it is the next step of this work, and
                    // this comment should go away when that lands rather than stay as the reason
                    // a failure is still quiet.
                    try? await self.fetch(force: true)
                }
            }
        }
    }

    /// Which calendar a change is about.
    ///
    /// `refreshed` carries the whole list, so it can name several, and it is the one case
    /// that cannot be reduced to a single id. `removed` is included deliberately: a
    /// calendar that has been deleted should send `fetch` to find nothing and go `.empty`,
    /// rather than leave a stale calendar on screen.
    private static func touchedIDs(in change: PinCalendarChange) -> Set<Int64> {
        switch change {
        case let .added(calendar), let .changed(calendar), let .removed(calendar):
            return [calendar.id]
        case let .refreshed(calendars):
            return Set(calendars.map(\.id))
        }
    }

    // MARK: - Projections read by the view

    /// The colour the main calendar's picker shows during a multi-select session. Lives
    /// in the store, because confirming the session needs the same value.
    public var selectedColor: PCColorOption? {
        store.state.multiSelectColor
    }

    public var isMultiSelectMode: Bool {
        store.state.multiSelectMode
    }

    public var isColorPickerDisabled: Bool {
        store.state.multiSelectMode
            && store.state.multiSelectColor != nil
            && !store.state.multiSelectDays.isEmpty
    }

    public func hasEvents(on date: Date) -> Bool {
        store.state.batches.contains { batch in
            batch.occurs(on: date, using: dataProvider)
        }
    }

    // MARK: - Commands

    /// Two-way control for the main calendar's multi-select colour.
    public var multiSelectColorBinding: Binding<PCColorOption?> {
        Binding(
            get: { self.store.state.multiSelectColor },
            set: { self.store.send(.setMultiSelectColor($0)) }
        )
    }

    /// Reports a tap on this panel's calendar to the reducer.
    ///
    /// The callback replaces watching `selectedDays` and inferring intent from its
    /// contents. `selectedDays` is now purely presentational: the store decides whether a
    /// tap selects a day, opens a batch, or opens the editor, and this panel just says
    /// "this day was tapped".
    public func installDayTapHandler() {
        daySelectionManager.onDayTapped = { [weak self] day in
            self?.send(.dayTappedInCalendar(day))
        }
    }

    public func clearDayTapHandler() {
        daySelectionManager.onDayTapped = nil
    }

    /// The main panel's column count changed (pinch to zoom). Persisted by the store's
    /// write chain, which coalesces trailing writes — so the 350 ms debounce and its
    /// `onDisappear` flush that used to live in `SingleCalendarView` are no longer needed.
    public func setNumberOfColumns(_ columns: Int) {
        send(.setNumberOfColumns(columns))
    }

    public func send(_ action: PCEventSelectionAction) {
        store.send(action)
        projectMarkers()
    }

    public func setMultiSelectMode(_ on: Bool) {
        send(.setMultiSelectMode(on))
    }

    public func setMultiSelectColor(_ color: PCColorOption?) {
        send(.setMultiSelectColor(color))
    }

    /// Confirms the session, which ends it and opens the batch editor on the batch it built.
    ///
    /// Nothing is declined: a session that could be confirmed always has days and a colour,
    /// and an empty one ends without opening anything.
    public func confirmMultiSelect() {
        send(.confirmMultiSelectTapped)
    }

    public func cancelMultiSelect() {
        send(.cancelMultiSelectTapped)
    }

    public func close() {
        send(.closeTapped)
    }

    // MARK: - Loading

    /// Throws if either read fails.
    ///
    /// Both reads previously degraded to "empty", and both were destructive rather than merely
    /// quiet:
    ///
    /// - A failed `calendar(id:)` became `state = .empty`, which is the same state a genuinely
    ///   deleted calendar produces and which draws `EmptyView`. A database hiccup therefore
    ///   rendered as a blank calendar with nothing to say.
    /// - A failed `eventBatches` became `[]` and that was handed to `.syncCalendar`, which
    ///   replaces `state.batches` wholesale. One transient read error emptied every batch from
    ///   the UI and destroyed any multi-select session in progress, and nothing could repair it
    ///   afterwards because no `.removed` change had been published — nothing was removed.
    ///
    /// Neither read is now allowed to reach those two lines with a value it invented.
    public func fetch(force: Bool = false) async throws {
        guard force || state != .content, !Task.isCancelled else { return }

        // Metadata through the domain port, so what is rendered is a `PinCalendar` and not
        // a persistence DTO this file would have to know the shape of.
        //
        // A thrown read and a `nil` are different facts and no longer collapse into one.
        // `nil` is the honest answer — there is no such calendar — and is still `.empty`.
        // A throw is *not* that answer, and is no longer allowed to become it.
        guard let calendar = try await persistence.calendar(id: calendarid) else {
            state = .empty
            return
        }

        // **Before** any mutation below, deliberately.
        //
        // Both reads are fallible, and anything assigned between them would be left updated
        // while `state` still reflected the *previous* calendar — a title from the new one over
        // markers from the old. Half-applying a fetch is worse than not applying it: the screen
        // is internally inconsistent and nothing says so. Reading both first makes the
        // mutation block below total — every assignment in it is reached or none is.
        //
        // It also restores the invariant the empty-batch fix was after: `.syncCalendar` replaces
        // `state.batches` wholesale, so it must never be handed an invented `[]`.
        let batches = try await persistence.eventBatches(calendarID: calendarid)

        label = calendar.name
        isArchived = calendar.isArchived
        // Build the matrix once per calendar. Rebuilding it on every fetch would swap out
        // the PCCalendarDayModel instances the views are bound to, so event updates would
        // not be observed and marked days would silently stop rendering.
        let resolvedColumns = columnCountResolver(calendar.numberOfColumns)
        if builtCalendarYear != calendar.year || yearModel.numberOfColumns != resolvedColumns {
            yearModel = PCCalendarModelBuilder.makeYearModel(
                from: dataProvider,
                year: calendar.year,
                daySelectionManager: daySelectionManager,
                numberOfCurrentMonth: dataProvider.numberOfCurrentMonth,
                numberOfColumns: calendar.numberOfColumns,
                columnCountResolver: columnCountResolver
            )
            builtCalendarYear = calendar.year
        }

        // The registry is the store's; this only tells it what was on disk.
        store.send(.syncCalendar(calendarID: calendarid, batches: batches))
        projectMarkers()
        state = .content
    }

    public func switchYear(to year: Int) {
        guard year != yearModel.year else { return }
        let columns = yearModel.numberOfColumns
        yearModel = PCCalendarModelBuilder.makeYearModel(
            from: dataProvider,
            year: year,
            daySelectionManager: daySelectionManager,
            numberOfCurrentMonth: dataProvider.numberOfCurrentMonth,
            numberOfColumns: columns,
            columnCountResolver: columnCountResolver
        )
        projectMarkers()
    }

    public func reset() {
        label = ""
        state = .empty
    }

    // MARK: - Projection

    /// Writes the store's marker payload into the main matrix, in place.
    ///
    /// Reads the same `dayEventColors` the store projects into the editor's calendar, so
    /// both panels agree on what a marked day is — including while a batch is staged,
    /// which is why the staged assembly is included.
    func projectMarkers() {
        PCCalendarMarkerProjector.apply(
            store.state.dayEventColors,
            to: yearModel,
            using: dataProvider
        )
    }
}
