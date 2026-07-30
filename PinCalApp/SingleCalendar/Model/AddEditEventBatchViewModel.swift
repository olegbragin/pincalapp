//
//  AddEditEventBatchViewModel.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 02.07.2026.
//

import Foundation
import Observation

@MainActor
@Observable
final class AddEditEventBatchViewModel {
    var isPresented: Bool = false
    // var selectedDayToShowEvents: Date?
    
    var eventBatchId: Int64 = 0
    var eventBatchName: String = "1"
    var eventListViewModel: EventListViewModel
    var eventBatchEvents: [EventDataSource] = []
    // var selectedDate: Date = .now
    var timestamp: UUID?
    
    var eventBatch: EventBatchDataSource?
    
    init(events: [EventDataSource] = []) {
        eventListViewModel = .init(events: events)
    }
    
    func save() -> Bool {
        guard
            !eventBatchName.isEmpty
        else { return false }
        eventBatch = EventBatchDataSource(
            name: eventBatchName,
            events: eventBatchEvents
        )
        return true
    }
    
    func prepare(with events: [EventDataSource]) {
        eventListViewModel.prepare(with: events)
    }
    
    func reset() {
        // selectedDayToShowEvents = nil
        isPresented = false
        
        eventBatchId = 0
        eventBatchName = ""
        // selectedDate = .now
        eventBatchEvents = []
        timestamp = nil
    }
}
