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
    var selectedDayToShowEvents: Date?
    
    var eventId: Int64 = 0
    var eventName: String = "1"
    var selectedColor: ColorOption?
    var selectedDate: Date = .now
    var timestamp: UUID?
    
    var event: EventDataSource?
    
    func save() -> Bool {
        guard
            !eventName.isEmpty,
            let selectedColor
        else { return false }
        event = EventDataSource(
            id: eventId,
            name: eventName,
            date: selectedDate,
            color: selectedColor.colorName,
            timestamp: timestamp
        )
        return true
    }
    
    func reset() {
        selectedDayToShowEvents = nil
        isPresented = false
        
        eventId = 0
        eventName = ""
        selectedColor = nil
        selectedDate = .now
        event = nil
        timestamp = nil
    }
}
