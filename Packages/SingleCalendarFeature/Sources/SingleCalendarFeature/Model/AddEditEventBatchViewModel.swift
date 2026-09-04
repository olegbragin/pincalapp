//
//  AddEditEventBatchViewModel.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 02.07.2026.
//

import Foundation
import CorePersistence
import DSKit
import CoreDomain
import Observation

@MainActor
@Observable
public final class AddEditEventBatchViewModel {
    // Shared session managers — injected, not owned.
    let eventsSelectionManager: PCEventsSelectionManager
    let daySelectionManager: PCCalendarDaySelectionManager

    var eventBatchId: Int64 = 0
    var eventBatchName: String = ""
    var selectedColor: PCColorOption?
    var date: Date?
    var timestamp: UUID?

    var eventBatch: EventBatchDataSource?

    var defaultColor: PCColorOption? {
        selectedColor ?? PCColorOption(eventsSelectionManager.events.first?.color ?? "")
    }

    var canSave: Bool {
        !eventBatchName.isEmpty && selectedColor != nil
    }

    var yearModel = PCCalendarYearModel()
    private let dataProvider = PCCalendarDataProvider()
    private var builtCalendarYear: Int?

    var preferredTitle: String? {
        title(compact: false)
    }

    var compactTitle: String? {
        title(compact: true)
    }

    init(
        eventsSelectionManager: PCEventsSelectionManager,
        daySelectionManager: PCCalendarDaySelectionManager
    ) {
        self.eventsSelectionManager = eventsSelectionManager
        self.daySelectionManager = daySelectionManager
        eventsSelectionManager.onEventsChanged = { [weak self] in
            self?.refreshCalendarDays()
        }
        setupCalendar()
    }

    convenience init(events: [EventDataSource] = []) {
        self.init(
            eventsSelectionManager: PCEventsSelectionManager(events: events),
            daySelectionManager: PCCalendarDaySelectionManager()
        )
    }

    func save() -> Bool {
        // Ensure any pending event edit (saved in child editor but not yet
        // applied via navigationDestination onChange) is flushed.
        guard
            !eventBatchName.isEmpty,
            let selectedColor
        else { return false }
        eventBatch = EventBatchDataSource(
            id: eventBatchId,
            name: eventBatchName,
            colorName: selectedColor.colorName,
            events: eventsSelectionManager.events,
            date: date,
            timestamp: timestamp
        )
        return true
    }

    func prepare(with events: [EventDataSource]) {
        eventsSelectionManager.prepare(with: events)
        setupCalendar()
    }

    func setupCalendar() {
        daySelectionManager.selectionMode = .multiple
        let year = calendarYear
        if yearModel.months.isEmpty || builtCalendarYear != year {
            yearModel.months = dataProvider.months(forYear: year).map {
                PCCalendarMonthModel(dto: $0, daySelectionManager: daySelectionManager)
            }
            yearModel.numberOfCurrentMonth = dataProvider.numberOfCurrentMonth
            builtCalendarYear = year
        }
        yearModel.scrollTargetDate = eventsSelectionManager.events.map(\.date).min() ?? date
        updateYearModel()
    }

    func toggleEvent(on date: Date) {
        if eventsSelectionManager.hasEvent(on: date) {
            eventsSelectionManager.removeEvent(on: date)
        } else {
            let colorName = selectedColor?.colorName ?? defaultColor?.colorName ?? PCColorOption.option1.colorName
            eventsSelectionManager.addEvent(
                .init(name: eventBatchName, date: date, color: colorName)
            )
        }
        daySelectionManager.selectedDays = []
        updateDay(for: date)
    }

    func refreshCalendarDays() {
        updateYearModel()
    }

    private var calendarYear: Int {
        if let firstEventDate = eventsSelectionManager.events.map(\.date).min() {
            return Calendar.current.component(.year, from: firstEventDate)
        }
        if let date {
            return Calendar.current.component(.year, from: date)
        }
        return Calendar.current.component(.year, from: Date())
    }

    private func updateYearModel() {
        let colorsByDay = eventColorsByDay()
        yearModel.months.forEach { month in
            month.weeks.forEach { week in
                week.days
                    .filter(\.isInCurrentMonth)
                    .forEach { day in
                        guard let dayDate = day.date else { return }
                        let colors = colorsByDay[Calendar.autoupdatingCurrent.startOfDay(for: dayDate)] ?? []
                        guard day.events != colors else { return }
                        day.events = colors
                    }
            }
        }
    }

    private func updateDay(for date: Date) {
        guard let day = dayModel(for: date) else { return }
        let colors = eventsSelectionManager.events
            .filter { Calendar.autoupdatingCurrent.isDate($0.date, inSameDayAs: date) }
            .map(\.color)
        guard day.events != colors else { return }
        day.events = colors
    }

    private func dayModel(for date: Date) -> PCCalendarDayModel? {
        var fallback: PCCalendarDayModel?
        for month in yearModel.months {
            for week in month.weeks {
                for day in week.days {
                    guard let dayDate = day.date,
                          Calendar.autoupdatingCurrent.isDate(dayDate, inSameDayAs: date)
                    else { continue }
                    if day.isInCurrentMonth { return day }
                    fallback = day
                }
            }
        }
        return fallback
    }

    private func eventColorsByDay() -> [Date: [String]] {
        var result: [Date: [String]] = [:]
        for event in eventsSelectionManager.events {
            result[Calendar.autoupdatingCurrent.startOfDay(for: event.date), default: []].append(event.color)
        }
        return result
    }

    func recolorAllEvents() {
        guard let selectedColor else { return }
        eventsSelectionManager.recolorAll(to: selectedColor.colorName)
        updateYearModel()
    }

    func reset() {
        eventBatchId = 0
        eventBatchName = ""
        selectedColor = nil
        date = nil
        timestamp = nil
        eventBatch = nil
        daySelectionManager.reset()
        yearModel.months = []
        eventsSelectionManager.reset()
    }

    private func title(compact: Bool) -> String? {
        let dates = eventsSelectionManager.events.map(\.date).sorted()
        guard let start = dates.first else {
            return date.map { singleDate($0, compact: compact) }
        }
        guard let end = dates.last, end > start else {
            return singleDate(start, compact: compact)
        }
        if compact {
            return compactPeriod(from: start, to: end)
        }
        return "\(fullDate(start)) - \(fullDate(end))"
    }

    private func singleDate(_ date: Date, compact: Bool) -> String {
        compact
            ? date.formatted(date: .numeric, time: .omitted)
            : fullDate(date)
    }

    private func fullDate(_ date: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let day = calendar.component(.day, from: date)
        let month = date.formatted(.dateTime.month(.abbreviated))
        let year = calendar.component(.year, from: date)
        return "\(day) \(month) \(year)"
    }

    private func compactPeriod(from start: Date, to end: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let startDay = start.formatted(.dateTime.day())
        let endDay = end.formatted(.dateTime.day())
        if calendar.component(.month, from: start) == calendar.component(.month, from: end),
           calendar.component(.year, from: start) == calendar.component(.year, from: end) {
            return "\(startDay)-\(endDay) \(end.formatted(.dateTime.month(.abbreviated).year()))"
        }
        return "\(startDay) \(start.formatted(.dateTime.month(.abbreviated))) - \(endDay) \(end.formatted(.dateTime.month(.abbreviated).year()))"
    }
}
