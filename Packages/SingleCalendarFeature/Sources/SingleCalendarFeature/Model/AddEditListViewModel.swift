//
//  AddEditListViewModel.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 07.07.2026.
//

import Foundation
import CorePersistence
import Observation

@MainActor
@Observable
public final class AddEditListViewModel {
    /// Shared events store. `PCEventsSelectionManager` owns the data; this view
    /// model is a thin adapter over it (kept for call sites that expect a list
    /// view model).
    let eventsSelectionManager: PCEventsSelectionManager

    private(set) var selectedDay: Date?

    var onEventsChanged: (() -> Void)? {
        didSet { eventsSelectionManager.onEventsChanged = onEventsChanged }
    }

    var events: [EventDataSource] { eventsSelectionManager.events }

    init(eventsSelectionManager: PCEventsSelectionManager) {
        self.eventsSelectionManager = eventsSelectionManager
    }

    convenience init(events: [EventDataSource] = []) {
        self.init(eventsSelectionManager: PCEventsSelectionManager(events: events))
    }

    func prepare(with events: [EventDataSource]) {
        eventsSelectionManager.prepare(with: events)
    }

    func apply(with event: EventDataSource) {
        eventsSelectionManager.apply(event)
    }

    func addEvent(_ event: EventDataSource) {
        eventsSelectionManager.addEvent(event)
    }

    func removeEvent(on date: Date) {
        eventsSelectionManager.removeEvent(on: date)
    }

    func removeEvents(at indexSet: IndexSet) {
        eventsSelectionManager.removeEvents(at: indexSet)
    }

    func hasEvent(on date: Date) -> Bool {
        eventsSelectionManager.hasEvent(on: date)
    }

    func recolorAll(to colorName: String) {
        eventsSelectionManager.recolorAll(to: colorName)
    }

    func reset() {
        eventsSelectionManager.reset()
        selectedDay = nil
    }
}
