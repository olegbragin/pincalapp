//
//  AddEditEventViewModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 15.03.2026.
//

import Foundation
import CorePersistence
import DSKit
import Observation

@MainActor
@Observable
public final class AddEditEventViewModel {
    var selectedDayToShowEvents: Date?
    
    var eventId: Int64 = 0
    var eventName: String = ""
    var selectedColor: PCColorOption?
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
    
    func update(from event: EventDataSource) {
        eventId = event.id
        eventName = event.name
        selectedColor = PCColorOption(event.color)
        selectedDate = event.date
        timestamp = event.timestamp
        selectedDayToShowEvents = event.date
    }
    
    func reset() {
        selectedDayToShowEvents = nil

        eventId = 0
        eventName = ""
        selectedColor = nil
        selectedDate = .now
        event = nil
        timestamp = nil
    }
}
