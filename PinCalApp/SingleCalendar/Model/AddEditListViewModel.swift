//
//  AddEditListViewModel.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 07.07.2026.
//

import Foundation
import Observation

@MainActor
@Observable
final class AddEditListViewModel {
    private(set) var events = [EventDataSource]()
    private(set) var selectedDay: Date?
    
    var onEventsChanged: (() -> Void)?
    
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
        addEditEventModel.selectedColor = PCColorOption(event.color)
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
        onEventsChanged?()
    }
    
    func addEvent(_ event: EventDataSource) {
        events.append(event.withTimestamp(UUID()))
        events.sort(by: { $0.date < $1.date })
    }
    
    func removeEvent(on date: Date) {
        events.removeAll {
            Calendar.current.isDate($0.date, inSameDayAs: date)
        }
    }
    
    func hasEvent(on date: Date) -> Bool {
        events.contains {
            Calendar.current.isDate($0.date, inSameDayAs: date)
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
