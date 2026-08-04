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
    
    var eventBatchId: Int64 = 0
    var eventBatchName: String = "1"
    var selectedColor: ColorOption?
    var eventListViewModel: EventListViewModel
    var date: Date?
    var timestamp: UUID?
    
    var eventBatch: EventBatchDataSource?
    
    init(events: [EventDataSource] = []) {
        eventListViewModel = .init(events: events)
    }
    
    func save() -> Bool {
        guard
            !eventBatchName.isEmpty,
            let selectedColor
        else { return false }
        eventBatch = EventBatchDataSource(
            id: eventBatchId,
            name: eventBatchName,
            colorName: selectedColor.colorName,
            events: eventListViewModel.events,
            date: date,
            timestamp: timestamp
        )
        return true
    }
    
    func prepare(with events: [EventDataSource]) {
        eventListViewModel.prepare(with: events)
    }
    
    func reset() {
        isPresented = false
        
        eventBatchId = 0
        eventBatchName = ""
        selectedColor = nil
        date = nil
        timestamp = nil
    }
}
