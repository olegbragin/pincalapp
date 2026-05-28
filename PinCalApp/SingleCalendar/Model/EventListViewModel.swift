//
//  EditListViewModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 31.03.2026.
//

import Foundation
import Observation

@MainActor
@Observable
final class EventListViewModel {    
    private(set) var events = [EventDataSource]()
    private(set) var selectedDay: Date?
    
    var addEditEventModel = AddEditEventViewModel()
    var eventsToChange = [EventDataSource]()
    var eventsToDelete = [EventDataSource]()
    var eventsSelectedToDelete = [EventDataSource]()
    var isEditing = false

    func removeEvents(at indexPaths: IndexSet) {
        indexPaths.forEach {
            let eventRemoved = events.remove(at: $0)
            eventsSelectedToDelete.append(eventRemoved)
        }
    }
    
    func apply(with event: EventDataSource) {
        if let eventToReplace = events.first(where: { $0.id == event.id || $0.timestamp == event.timestamp }) {
            events.replace([eventToReplace], with: [event])
        } else {
            events.append(event)
        }
        eventsToChange = events
    }
    
    func prepare(with events: [EventDataSource], and selectedDay: Date?) {
        self.selectedDay = selectedDay
        self.events = events.sorted(by: { $0.date < $1.date })
    }
    
    func prepareAddEditViewModel(with event: EventDataSource) {
        addEditEventModel.selectedDayToShowEvents = selectedDay ?? Date()
        addEditEventModel.eventName = event.name
        addEditEventModel.eventId = event.id
        addEditEventModel.selectedColor = ColorOption(event.color)
        addEditEventModel.selectedDate = event.date
        addEditEventModel.timestamp = event.timestamp
        addEditEventModel.isPresented = true
    }
    
    func commitDelete() {
        eventsToDelete = eventsSelectedToDelete
        eventsSelectedToDelete = []
        isEditing = false
    }
    
    func cancel() {
        events.append(contentsOf: eventsSelectedToDelete)
        eventsSelectedToDelete = []
        isEditing = false
        addEditEventModel.reset()
    }
    
    func reset() {
        events = []
        eventsSelectedToDelete = []
        isEditing = false
        addEditEventModel.reset()
    }
}
