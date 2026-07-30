//
//  AddEditEventBatchListViewModel.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 08.07.2026.
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AddEditEventBatchListViewModel {
    private(set) var eventBatches = [EventBatchDataSource]()
    private(set) var selectedDay: Date?
    
    var addEditEventBatchModel = AddEditEventBatchViewModel()
    // var eventsToChange = [EventDataSource]()
    // var eventsToDelete = [EventDataSource]()
    // var eventsSelectedToDelete = [EventDataSource]()
    var isEditing = false

//    func removeEvents(at indexPaths: IndexSet) {
//        indexPaths.forEach {
//            let eventRemoved = eventBatches.remove(at: $0)
//            eventsSelectedToDelete.append(eventRemoved)
//        }
//    }
    
//    func apply(with event: EventDataSource) {
//        if let eventToReplace = eventBatches.first(where: { $0.id == event.id || $0.timestamp == event.timestamp }) {
//            eventBatches.replace([eventToReplace], with: [event])
//        } else {
//            eventBatches.append(event)
//        }
//        eventsToChange = eventBatches
//    }
    
    func prepare(with eventBatches: [EventBatchDataSource], and selectedDay: Date?) {
        self.selectedDay = selectedDay
        self.eventBatches = eventBatches
    }
    
//    func prepareAddEditViewModel(with event: EventDataSource) {
//        addEditEventModel.selectedDayToShowEvents = selectedDay ?? Date()
//        addEditEventModel.eventName = event.name
//        addEditEventModel.eventId = event.id
//        addEditEventModel.selectedColor = ColorOption(event.color)
//        addEditEventModel.selectedDate = event.date
//        addEditEventModel.timestamp = event.timestamp
//        addEditEventModel.isPresented = true
//    }
//    
//    func commitDelete() {
//        eventsToDelete = eventsSelectedToDelete
//        eventsSelectedToDelete = []
//        isEditing = false
//    }
    
    func cancel() {
        // eventBatches.append(contentsOf: eventsSelectedToDelete)
        // eventsSelectedToDelete = []
        isEditing = false
        // addEditEventModel.reset()
    }
    
    func reset() {
        eventBatches = []
        // eventsSelectedToDelete = []
        isEditing = false
        // addEditEventModel.reset()
    }
}

extension EventBatchDataSource {
    var color: Color {
        guard let eventCOmmonCOlor = events.first?.color else { return .clear }
        return Color(eventCOmmonCOlor)
    }
}
