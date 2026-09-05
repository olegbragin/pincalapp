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
    // Shared session manager — injected, not owned. It owns the events, the
    // batch color and the calendar (year model); this view model only carries
    // the batch metadata and reads/writes the session through the manager.
    let eventsSelectionManager: PCEventsSelectionManager

    var eventBatchId: Int64 = 0
    var eventBatchName: String = ""
    var date: Date?
    var timestamp: UUID?

    var eventBatch: EventBatchDataSource?

    var daySelectionManager: PCCalendarDaySelectionManager {
        eventsSelectionManager.daySelectionManager
    }

    var yearModel: PCCalendarYearModel {
        eventsSelectionManager.yearModel
    }

    /// The batch's selected color. It lives in the shared `eventsSelectionManager`
    /// so the events list, batch editor and event editor all agree on it; setting
    /// it rewrites every event's color in the batch.
    var selectedColor: PCColorOption? {
        get { eventsSelectionManager.selectedColor }
        set { eventsSelectionManager.setBatchColor(newValue) }
    }

    var defaultColor: PCColorOption? {
        selectedColor ?? PCColorOption(eventsSelectionManager.events.first?.color ?? "")
    }

    var canSave: Bool {
        !eventBatchName.isEmpty && selectedColor != nil
    }

    var preferredTitle: String? {
        title(compact: false)
    }

    var compactTitle: String? {
        title(compact: true)
    }

    init(eventsSelectionManager: PCEventsSelectionManager) {
        self.eventsSelectionManager = eventsSelectionManager
        eventsSelectionManager.setupCalendar()
    }

    convenience init(events: [EventDataSource] = []) {
        self.init(eventsSelectionManager: PCEventsSelectionManager(events: events))
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
    }

    /// Loads the batch-editing session from an existing batch (or a fresh,
    /// empty one for a new day) into this session. The caller (the coordinator
    /// or the batch list) drives preparation; this view model is decoupled from
    /// the batch list and is connected to it only via the shared manager.
    func load(_ eventBatch: EventBatchDataSource?, selectedDay: Date? = nil) {
        if let eventBatch {
            eventBatchId = eventBatch.id
            eventBatchName = eventBatch.name
            date = eventBatch.date
            timestamp = eventBatch.timestamp
            prepare(with: eventBatch.events)
            eventsSelectionManager.setBatchColor(PCColorOption(eventBatch.colorName) ?? .option1)
        } else {
            // New batch: the caller already staged the starting events (added
            // events or a placeholder) in the shared manager, so don't clear them
            // here — just seed the metadata from the first event.
            eventBatchId = 0
            let firstEvent = eventsSelectionManager.events.first
            eventBatchName = firstEvent?.name ?? ""
            date = selectedDay
            timestamp = UUID()
            eventsSelectionManager.setupCalendar()
            eventsSelectionManager.setBatchColor(PCColorOption(firstEvent?.color ?? "") ?? .option1)
        }
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
    }

    func setupCalendar() {
        eventsSelectionManager.setupCalendar()
        if eventsSelectionManager.yearModel.scrollTargetDate == nil {
            eventsSelectionManager.yearModel.scrollTargetDate = date
        }
    }

    func recolorAllEvents() {
        guard let selectedColor else { return }
        eventsSelectionManager.setBatchColor(selectedColor)
    }

    func reset() {
        eventBatchId = 0
        eventBatchName = ""
        date = nil
        timestamp = nil
        eventBatch = nil
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
