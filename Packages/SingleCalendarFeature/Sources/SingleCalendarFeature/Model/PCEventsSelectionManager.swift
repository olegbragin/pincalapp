//
//  PCEventsSelectionManager.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 04.09.2026.
//

import Foundation
import CorePersistence
import Observation

/// Shared, observable store for the events being edited in a batch editor
/// session. It owns no view models — callers (the events list view, the batch
/// editor, the single-event editor) observe `events` and drive mutations
/// through it. Day selection is handled separately by
/// `PCCalendarDaySelectionManager`.
@MainActor
@Observable
public final class PCEventsSelectionManager {
    private(set) var events: [EventDataSource] = []

    /// Calendar used for all "is the same day" comparisons. Injected so the
    /// manager doesn't silently depend on the process calendar.
    private let calendar: Calendar

    /// Invoked whenever a mutation that should refresh the calendar markers
    /// happens (e.g. `apply`, `removeEvents`).
    var onEventsChanged: (() -> Void)?

    public init(events: [EventDataSource] = [], calendar: Calendar = .autoupdatingCurrent) {
        self.events = events
        self.calendar = calendar
    }

    func prepare(with events: [EventDataSource]) {
        self.events = events
            .sorted(by: { $0.date < $1.date })
            .map { event in
                event.timestamp == nil ? event.withTimestamp(UUID()) : event
            }
    }

    func hasEvent(on date: Date) -> Bool {
        events.contains {
            calendar.isDate($0.date, inSameDayAs: date)
        }
    }

    func addEvent(_ event: EventDataSource) {
        events.append(event.withTimestamp(UUID()))
        events.sort(by: { $0.date < $1.date })
    }

    func removeEvent(on date: Date) {
        events.removeAll {
            calendar.isDate($0.date, inSameDayAs: date)
        }
    }

    /// Removes the events at the given indices (used by the List's edit-mode
    /// delete/`onDelete`), then notifies listeners so the calendar refreshes.
    func removeEvents(at indexSet: IndexSet) {
        indexSet.sorted(by: >).forEach { events.remove(at: $0) }
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
        onEventsChanged?()
    }

    func recolorAll(to colorName: String) {
        events = events.map { $0.withColor(colorName) }
    }

    func reset() {
        events = []
    }
}
