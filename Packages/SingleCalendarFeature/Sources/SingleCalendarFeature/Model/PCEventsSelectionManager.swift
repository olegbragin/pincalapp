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
/// being edited, the batch's selected color, and the calendar (year model) shown
/// in the batch editor. All three models that participate in batch editing
/// (SingleCalendarModel, the batch list, the batch editor) depend on this
/// manager and communicate through it. Day selection is handled separately by
/// the injected `PCCalendarDaySelectionManager`.
@MainActor
@Observable
public final class PCEventsSelectionManager {
    private(set) var events: [EventDataSource] = []
    private(set) var selectedColor: PCColorOption?

    /// The calendar shown in the batch editor. Kept here so every mutation that
    /// changes the events also refreshes the day markers, and so the calendar
    /// and the events list always agree.
    let yearModel: PCCalendarYearModel = PCCalendarYearModel()

    /// Calendar used for all "is the same day" comparisons. Injected so the
    /// manager doesn't silently depend on the process calendar.
    private let calendar: Calendar

    private let dataProvider: PCCalendarDataProvider
    let daySelectionManager: PCCalendarDaySelectionManager
    private var builtCalendarYear: Int?

    /// Number of columns the batch editor's calendar should show. It mirrors
    /// the owning calendar's column count (and the `-UITestColumns` launch
    /// argument) so the batch editor's day cells match the main calendar and
    /// remain reliably tappable in UI tests. Set by `SingleCalendarModel.fetch`
    /// whenever a calendar is opened.
    var numberOfColumns: Int = 3

    /// Invoked whenever a mutation that should refresh other listeners happens.
    var onEventsChanged: (() -> Void)?

    public init(
        events: [EventDataSource] = [],
        calendar: Calendar = .autoupdatingCurrent,
        dataProvider: PCCalendarDataProvider = PCCalendarDataProvider(),
        daySelectionManager: PCCalendarDaySelectionManager = PCCalendarDaySelectionManager(),
        numberOfColumns: Int = 3
    ) {
        self.events = events
        self.calendar = calendar
        self.dataProvider = dataProvider
        self.daySelectionManager = daySelectionManager
        self.numberOfColumns = numberOfColumns
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
            calendar.isDate($0.date, inSameDayAs: date)
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
            calendar.isDate($0.date, inSameDayAs: date)
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
            yearModel.months = dataProvider.months(forYear: year).map {
                PCCalendarMonthModel(dto: $0, daySelectionManager: daySelectionManager)
            }
            yearModel.numberOfCurrentMonth = dataProvider.numberOfCurrentMonth
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
                        let colors = colorsByDay[calendar.startOfDay(for: dayDate)] ?? []
                        guard day.events != colors else { return }
                        day.events = colors
                    }
            }
        }
    }

    private var calendarYear: Int {
        if let firstEventDate = events.map(\.date).min() {
            return calendar.component(.year, from: firstEventDate)
        }
        return calendar.component(.year, from: Date())
    }

    private func eventColorsByDay() -> [Date: [String]] {
        var result: [Date: [String]] = [:]
        for event in events {
            result[calendar.startOfDay(for: event.date), default: []].append(event.color)
        }
        return result
    }
}
