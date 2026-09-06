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
    let yearModel: PCCalendarYearDataSource = PCCalendarYearDataSource()

    /// Calendar/date logic lives in the data provider so the manager doesn't
    /// silently depend on the process calendar.
    private let dataProvider: PCCalendarDataProvider
    let daySelectionManager: PCCalendarDaySelectionManager
    private var builtCalendarYear: Int?

    /// The calendar whose batches are being edited. Set by `SingleCalendarModel`
    /// when a calendar is opened, so the manager can resolve and commit batches.
    private(set) var calendarId: Int64 = 0

    /// The calendar's batches — the single source of truth for batch editing.
    /// `SingleCalendarModel` reads/writes these through the manager.
    var batches: [EventBatchDataSource] = []

    /// Used to persist committed batches. Injected from the session; `nil` in
    /// unit tests that don't touch persistence.
    private let cache: CalendarCache?

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

    public init(
        events: [EventDataSource] = [],
        cache: CalendarCache? = nil,
        dataProvider: PCCalendarDataProvider = PCCalendarDataProvider(),
        daySelectionManager: PCCalendarDaySelectionManager = PCCalendarDaySelectionManager(),
        numberOfColumns: Int = 3
    ) {
        self.events = events
        self.cache = cache
        self.dataProvider = dataProvider
        self.daySelectionManager = daySelectionManager
        self.numberOfColumns = numberOfColumns
    }

    /// Configures the manager for the calendar being edited. `SingleCalendarModel`
    /// calls this whenever a calendar is fetched so the manager can resolve and
    /// commit batches for that calendar.
    func setCalendar(id: Int64, batches: [EventBatchDataSource]) {
        self.calendarId = id
        self.batches = batches
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

    /// Commits an edited batch into the calendar's batch list and persists it.
    /// Replaces an existing batch (matched by its merge key) or appends a new one.
    func commit(_ eventBatch: EventBatchDataSource?) {
        guard let eventBatch else { return }
        let batchKey = key(for: eventBatch)
        batches.removeAll(where: { key(for: $0) == batchKey })
        if !eventBatch.events.isEmpty {
            batches.append(eventBatch)
        }
        persistBatches()
    }

    /// Removes the given batches from the calendar's batch list and persists it.
    func deleteBatches(_ batches: [EventBatchDataSource]) {
        for batch in batches {
            self.batches.removeAll(where: { key(for: $0) == key(for: batch) })
        }
        persistBatches()
    }

    func reset() {
        events = []
        selectedColor = nil
        yearModel.months = []
        builtCalendarYear = nil
    }

    func setupCalendar() {
        yearModel.numberOfColumns = numberOfColumns
        let year = calendarYear
        if yearModel.months.isEmpty || builtCalendarYear != year {
            let model = dataProvider.makeYearModel(
                year: year,
                numberOfColumns: numberOfColumns,
                daySelectionManager: daySelectionManager
            )
            yearModel.months = model.months
            yearModel.numberOfCurrentMonth = model.numberOfCurrentMonth
            builtCalendarYear = year
        }
        yearModel.scrollTargetDate = events.map(\.date).min()
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

    private var calendarYear: Int {
        if let firstEventDate = events.map(\.date).min() {
            return dataProvider.year(of: firstEventDate)
        }
        return dataProvider.year(of: Date())
    }

    private func eventColorsByDay() -> [Date: [String]] {
        var result: [Date: [String]] = [:]
        for event in events {
            result[dataProvider.startOfDay(for: event.date), default: []].append(event.color)
        }
        return result
    }
}
