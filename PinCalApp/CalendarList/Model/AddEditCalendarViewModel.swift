//
//  AddEditCalendarViewModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 18.03.2026.
//

import Observation

@Observable
final class AddEditCalendarViewModel {
    var id: Int64 = 0
    var label: String = ""
    var calendar: CalendarDataSource?
    
    func save() -> Bool {
        guard !label.isEmpty else { return false }
        calendar = CalendarDataSource(id: id, name: label, year: 2026, numberOfColumns: 1)
        return true
    }
    
    func reset() {
        id = 0
        label = ""
    }
}

