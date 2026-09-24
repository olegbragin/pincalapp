//
//  PCEventsSelectionManager.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 04.09.2026.
//

import Foundation
import CorePersistence
import CoreDomain
import DSKit
import Observation

/// Shared, observable store for a batch-editing session. It owns the events
/// being edited, the batch's selected color, the calendar (year model) shown in
/// the batch editor, and (as the source of truth) the calendar's batches. All
/// three models that participate in batch editing (SingleCalendarModel, the
/// batch list, the batch editor) depend on this manager and communicate through
/// it. Day selection is handled separately by the injected
/// `PCCalendarDaySelectionManager`.
@MainActor
@Observable
public final class PCEventsSelectionManager {
    private(set) var events: [EventDataSource] = []
    private(set) var selectedColor: PCColorOption?

    /// The calendar shown in the batch editor. Kept here so every mutation that
    /// changes the events also refreshes the day markers, and so the calendar
    /// and the events list always agree.
    private(set) var yearModel: PCCalendarYearModel

    /// Calendar/date logic lives in the data provider so the manager doesn't
    /// silently depend on the process calendar.
    private let dataProvider: PCCalendarDataProvider
    let daySelectionManager: PCCalendarDaySelectionManager

    /// The calendar whose batches are being edited. Set by `SingleCalendarModel`
    /// when a calendar is opened, so the manager can resolve and commit batches.
    private(set) var calendarId: Int64 = 0

    /// The calendar's batches — the single source of truth for batch editing.
    /// `SingleCalendarModel` reads/writes these through the manager.
    var batches: [EventBatchDataSource] = []

    /// Used to persist committed batches. Injected from the session; `nil` in
    /// unit tests that don't touch persistence.
    private let cache: CalendarCache?

    /// Maps a staged (not-yet-persisted) batch's `timestamp` to the id the
    /// store assigned to it once it was reloaded through `setCalendar`.
    ///
    /// A batch staged in this session is committed with `id == 0` and carries a
    /// `timestamp` as its identity (see `key(for:)`). The store drops that
    /// `timestamp` and assigns a real `id`, so the moment the reload arrives the
    /// same logical batch would otherwise look like a *different* batch: a later
    /// commit keyed `.pending(timestamp)` would not match the reloaded
    /// `.persisted(id)` row and would append a duplicate (the reported bug).
    /// This map re-establishes that link so later commits update in place.
    private var persistedIDsByPendingTimestamp: [UUID: Int64] = [:]

    /// Number of columns the batch editor's calendar should show. It mirrors
    /// the owning calendar's column count (and the `-UITestColumns` launch
    /// argument) so the batch editor's day cells match the main calendar and
    /// remain reliably tappable in UI tests. Set by `SingleCalendarModel.fetch`
    /// whenever a calendar is opened.
    var numberOfColumns: Int = 3

    /// Invoked whenever a mutation that should refresh other listeners happens.
    var onEventsChanged: (() -> Void)?

    /// Invoked when a single event is applied (e.g. saved from the event editor).
    /// Lets the batch editor persist the batch right after an event edit.
    var onEventApplied: (() -> Void)?

    /// Resolves the effective column count for a year model. Injected so callers
    /// (e.g. UI-test launch arguments) can override the calendar's natural count
    /// without the data provider knowing about test infrastructure.
    private let columnCountResolver: (Int) -> Int

    public init(
        events: [EventDataSource] = [],
        cache: CalendarCache? = nil,
        dataProvider: PCCalendarDataProvider = PCCalendarDataProvider(),
        daySelectionManager: PCCalendarDaySelectionManager = PCCalendarDaySelectionManager(),
        numberOfColumns: Int = 3,
        columnCountResolver: @escaping (Int) -> Int = { $0 }
    ) {
        self.events = events
        self.cache = cache
        self.dataProvider = dataProvider
        self.daySelectionManager = daySelectionManager
        self.numberOfColumns = numberOfColumns
        self.columnCountResolver = columnCountResolver
        self.yearModel = Self.makeYearModel(
            from: dataProvider,
            year: nil,
            numberOfCurrentMonth: dataProvider.numberOfCurrentMonth,
            numberOfColumns: numberOfColumns,
            daySelectionManager: daySelectionManager,
            columnCountResolver: columnCountResolver
        )
    }

    /// The single factory for the year model. The feature layer owns the
    /// calendar/date logic, so the model is always created here with its whole
    /// month matrix rather than assembled from separate assignments.
    private static func makeYearModel(
        from dataProvider: PCCalendarDataProvider,
        year: Int?,
        numberOfCurrentMonth: Int,
        numberOfColumns: Int,
        daySelectionManager: PCCalendarDaySelectionManager,
        columnCountResolver: @escaping (Int) -> Int
    ) -> PCCalendarYearModel {
        PCCalendarModelBuilder.makeYearModel(
            from: dataProvider,
            year: year,
            daySelectionManager: daySelectionManager,
            numberOfCurrentMonth: numberOfCurrentMonth,
            numberOfColumns: numberOfColumns,
            columnCountResolver: columnCountResolver
        )
    }

    /// Configures the manager for the calendar being edited. `SingleCalendarModel`
    /// calls this whenever a calendar is fetched so the manager can resolve and
    /// commit batches for that calendar.
    func setCalendar(id: Int64, batches: [EventBatchDataSource]) {
        self.calendarId = id
        // A batch staged during this session is committed as id == 0 with a
        // timestamp identity. If it was already persisted (e.g. auto-committed
        // by an event edit), the freshly loaded row carries the store-assigned
        // id and a dropped timestamp — so relate the two by content. A later
        // commit of the staged batch then updates that row instead of appending
        // a duplicate (the reported bug: saving the batch editor after saving an
        // event created a second batch with the same event).
        let stagedBeforeReload = self.batches.filter { $0.id == 0 && $0.timestamp != nil }
        self.batches = batches
        guard !stagedBeforeReload.isEmpty else { return }
        for staged in stagedBeforeReload {
            guard let pendingTimestamp = staged.timestamp else { continue }
            // The twin is the fresh batch with the same content and no timestamp
            // (timestamps are never persisted).
            guard let persisted = batches.first(where: { $0.timestamp == nil && contentEquals(staged, $0) }) else { continue }
            persistedIDsByPendingTimestamp[pendingTimestamp] = persisted.id
        }
    }

    /// Compares two batches ignoring their identity (id and timestamp), matching
    /// only the user-visible content: name, color, date, and the event set
    /// (compared by name, color, and day).
    private func contentEquals(_ lhs: EventBatchDataSource, _ rhs: EventBatchDataSource) -> Bool {
        guard lhs.name == rhs.name,
              lhs.colorName == rhs.colorName,
              (lhs.date ?? lhs.events.first?.date) == (rhs.date ?? rhs.events.first?.date),
              lhs.events.count == rhs.events.count,
              !lhs.events.isEmpty else {
            return false
        }
        let lhsSorted = lhs.events.sorted { $0.date < $1.date }
        let rhsSorted = rhs.events.sorted { $0.date < $1.date }
        return zip(lhsSorted, rhsSorted).allSatisfy { lhsEvent, rhsEvent in
            lhsEvent.name == rhsEvent.name
                && lhsEvent.color == rhsEvent.color
                && dataProvider.isSameDay(lhsEvent.date, rhsEvent.date)
        }
    }

    func prepare(with events: [EventDataSource]) {
        self.events = events
            .sorted(by: { $0.date < $1.date })
            .map { event in
                event.timestamp == nil ? event.withTimestamp(UUID()) : event
            }
        // Staging events marks the start of a batch-editing session. The batch
        // editor needs multi-select day toggling, so switch the shared selection
        // mode here. This is intentionally NOT done in `setupCalendar`, which
        // also runs when the editor's view model is re-created during a
        // navigation transition (e.g. on dismiss) — doing it there would leave
        // the main calendar stuck in multi-select mode.
        daySelectionManager.selectionMode = .multiple
        // Clear any day still selected on the main calendar. Without this, the
        // editor's `onChange(of: selectedDays)` fires with a set that mixes the
        // newly tapped day with the leftover one, so the first editor tap toggles
        // the wrong day (and can remove the placeholder event on the anchor day).
        daySelectionManager.selectedDays = []
        setupCalendar()
    }

    /// Sets the batch color and rewrites every event's color to it. This is how
    /// a batch color is applied — it propagates to all events in the batch.
    func setBatchColor(_ color: PCColorOption?) {
        selectedColor = color
        if let color {
            events = events.map { $0.withColor(color.colorName) }
        }
        updateYearModel()
        onEventsChanged?()
    }

    func hasEvent(on date: Date) -> Bool {
        events.contains {
            dataProvider.isSameDay($0.date, date)
        }
    }

    func addEvent(_ event: EventDataSource) {
        events.append(event.withTimestamp(UUID()))
        events.sort(by: { $0.date < $1.date })
        updateYearModel()
        onEventsChanged?()
    }

    func removeEvent(on date: Date) {
        events.removeAll {
            dataProvider.isSameDay($0.date, date)
        }
        updateYearModel()
        onEventsChanged?()
    }

    /// Removes the events at the given indices (used by the List's edit-mode
    /// delete/`onDelete`), then notifies listeners so the calendar refreshes.
    func removeEvents(at indexSet: IndexSet) {
        indexSet.sorted(by: >).forEach { events.remove(at: $0) }
        updateYearModel()
        onEventsChanged?()
    }

    /// Replaces or appends an event (result of editing a single event).
    func apply(_ event: EventDataSource) {
        if let indexToReplace = events.firstIndex(where: { $0.timestamp == event.timestamp }) {
            events[indexToReplace] = event
        } else if event.id != 0, let indexToReplace = events.firstIndex(where: { $0.id == event.id }) {
            events[indexToReplace] = event
        } else {
            events.append(event)
        }
        updateYearModel()
        onEventsChanged?()
        onEventApplied?()
    }

    /// Resolves a batch by its persisted id.
    func batch(withId id: Int64) -> EventBatchDataSource? {
        batches.first { $0.id == id }
    }

    /// Returns the batches that fall on the given day.
    func batches(for day: Date) -> [EventBatchDataSource] {
        batches.filter { batch in
            batch.events.contains { event in
                dataProvider.isSameDay(event.date, day)
            } || (batch.date.map { dataProvider.isSameDay($0, day) } ?? false)
        }
    }

    /// Commits an edited batch into the calendar's batch list and persists it.
    /// Replaces an existing batch (matched by its merge key) or appends a new one.
    func commit(_ eventBatch: EventBatchDataSource?) {
        guard let eventBatch else { return }
        // If this staged batch was already persisted (e.g. auto-committed by an
        // event edit) before the user hit Save, rewrite its id to the persisted
        // one so the merge key resolves to the existing row rather than appending
        // a second batch (the reported bug).
        let batchToCommit: EventBatchDataSource
        if eventBatch.id == 0, let timestamp = eventBatch.timestamp,
           let persistedID = persistedIDsByPendingTimestamp[timestamp] {
            batchToCommit = eventBatch.with(id: persistedID)
        } else {
            batchToCommit = eventBatch
        }
        let batchKey = key(for: batchToCommit)
        batches.removeAll(where: { key(for: $0) == batchKey })
        if !batchToCommit.events.isEmpty {
            batches.append(batchToCommit)
        }
        persistBatches()
    }

    /// Removes the given batches from the calendar's batch list and persists it.
    func deleteBatches(_ batches: [EventBatchDataSource]) {
        for batch in batches {
            if batch.id != 0 {
                persistedIDsByPendingTimestamp = persistedIDsByPendingTimestamp.filter { $0.value != batch.id }
            }
            if let timestamp = batch.timestamp {
                persistedIDsByPendingTimestamp.removeValue(forKey: timestamp)
            }
            self.batches.removeAll(where: { key(for: $0) == key(for: batch) })
        }
        persistBatches()
    }

    func reset() {
        events = []
        selectedColor = nil
        yearModel.months = []
    }

    func setupCalendar() {
        yearModel.numberOfColumns = numberOfColumns
        // The displayed year is only ever changed by the user (via `switchYear`);
        // here we just ensure the model is built for its current year.
        if yearModel.months.isEmpty {
            yearModel = Self.makeYearModel(
                from: dataProvider,
                year: yearModel.year,
                numberOfCurrentMonth: dataProvider.numberOfCurrentMonth,
                numberOfColumns: numberOfColumns,
                daySelectionManager: daySelectionManager,
                columnCountResolver: columnCountResolver
            )
        }
        // The scroll target is only defaulted here (from the earliest event);
        // an explicit anchor (the selected day or the batch's date) set by the
        // batch editor takes precedence and is never overwritten.
        if yearModel.scrollTargetMonth == nil {
            yearModel.scrollTargetMonth = events.map(\.date).min().map { dataProvider.month(of: $0) }
        }
        updateYearModel()
    }

    /// Resolves the month for a date via the data provider and sets it as the
    /// calendar's scroll target (used as a fallback when there are no events).
    func setScrollTargetMonth(to date: Date?) {
        yearModel.scrollTargetMonth = date.map { dataProvider.month(of: $0) }
    }

    /// Switches the batch editor's calendar to a different year, rebuilding the
    /// month matrix for it. The feature layer owns the builder, so the model
    /// stays a pure state holder.
    func switchYear(to year: Int) {
        guard year != yearModel.year else { return }
        yearModel = Self.makeYearModel(
            from: dataProvider,
            year: year,
            numberOfCurrentMonth: dataProvider.numberOfCurrentMonth,
            numberOfColumns: yearModel.numberOfColumns,
            daySelectionManager: daySelectionManager,
            columnCountResolver: columnCountResolver
        )
        updateYearModel()
    }

    /// Rebuilds the day markers from the current events. Because the day views
    /// live inside a LazyVGrid and don't re-evaluate when a day model's `events`
    /// mutates in place, we rebuild the months so the calendar re-renders.
    func updateYearModel() {
        let colorsByDay = eventColorsByDay()
        yearModel.months.forEach { month in
            month.weeks.forEach { week in
                week.days
                    .filter(\.isInCurrentMonth)
                    .forEach { day in
                        guard let dayDate = day.date else { return }
                        let colors = colorsByDay[dataProvider.startOfDay(for: dayDate)] ?? []
                        guard day.events != colors else { return }
                        day.events = colors
                    }
            }
        }
    }

    enum BatchMergeKey: Hashable {
        case persisted(Int64)
        case pending(UUID)
        case unsaved(Int)
    }

    func key(for batch: EventBatchDataSource) -> BatchMergeKey {
        if batch.id != 0 {
            return .persisted(batch.id)
        }
        if let timestamp = batch.timestamp {
            return .pending(timestamp)
        }
        return .unsaved(batch.hashValue)
    }

    private func persistBatches() {
        guard let cache, calendarId != 0 else { return }
        let calendarIdSnapshot = calendarId
        let batchesSnapshot = batches
        Task {
            guard var calendar = try? await cache.getCalendar(id: calendarIdSnapshot) else { return }
            calendar.eventBatches = batchesSnapshot
            try? await cache.updateCalendar(calendar)
        }
    }

    private func eventColorsByDay() -> [Date: [String]] {
        var result: [Date: [String]] = [:]
        for event in events {
            result[dataProvider.startOfDay(for: event.date), default: []].append(event.color)
        }
        return result
    }
}
