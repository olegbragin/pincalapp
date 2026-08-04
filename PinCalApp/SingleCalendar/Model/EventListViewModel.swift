//
//  EventListViewModel.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 07.07.2026.
//

import Foundation
import Observation

@MainActor
@Observable
final class EventListViewModel {
    private(set) var events = [EventDataSource]()
    private(set) var selectedDay: Date?
    
    var addEditEventModel = AddEditEventViewModel()
    
    init(events: [EventDataSource] = [EventDataSource]()) {
        self.events = events
    }
    
    func prepare(with events: [EventDataSource]) {
        self.events = events
            .sorted(by: { $0.date < $1.date })
            .map { event in
                event.timestamp == nil ? event.withTimestamp(UUID()) : event
            }
    }
    
    func prepareAddEditViewModel(with event: EventDataSource) {
        addEditEventModel.selectedDayToShowEvents = event.date
        addEditEventModel.eventName = event.name
        addEditEventModel.eventId = event.id
        addEditEventModel.selectedColor = ColorOption(event.color)
        addEditEventModel.selectedDate = event.date
        addEditEventModel.timestamp = event.timestamp
        addEditEventModel.isPresented = true
    }
    
    func apply(with event: EventDataSource) {
        if let indexToReplace = events.firstIndex(where: { $0.timestamp == event.timestamp }) {
            events[indexToReplace] = event
        } else if event.id != 0, let indexToReplace = events.firstIndex(where: { $0.id == event.id }) {
            events[indexToReplace] = event
        } else {
            events.append(event)
        }
    }
    
    func recolorAll(to colorName: String) {
        events = events.map { $0.withColor(colorName) }
    }
    
    func reset() {
        events = []
        selectedDay = nil
        addEditEventModel.reset()
    }
}
