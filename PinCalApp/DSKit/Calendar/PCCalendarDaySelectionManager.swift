//
//  USCalendarDaySelectionManager.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 27.04.2026.
//

import Foundation
import Observation

@MainActor
@Observable
final class USCalendarDaySelectionManager {
    var selectedDays: Set<Date> = []
    var selectionMode: USCalendarSelectionMode = .single
    
    func select(day: USCalendarDayModel) {
        guard
            day.isInCurrentMonth,
            let selectedDay = day.date
        else { return }
        switch selectionMode {
        case .single:
            selectedDays.removeAll()
            selectedDays.insert(selectedDay)
        case .multiple:
            if !selectedDays.contains(selectedDay) {
                selectedDays.insert(selectedDay)
            } else {
                selectedDays.remove(selectedDay)
            }
        }
    }
    
    func toggleSelectionMode() {
        let currentSelectionMode = selectionMode
        selectionMode = currentSelectionMode == .single ? .multiple : .single
    }
    
    func reset() {
        selectedDays.removeAll()
        selectedDays = []
    }
}
