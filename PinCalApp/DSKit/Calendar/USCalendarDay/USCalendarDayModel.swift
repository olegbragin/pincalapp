//
//  USCalendarDayModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 01.02.2026.
//

import Foundation

@Observable
final class USCalendarDayModel: Identifiable {
    let id = UUID()
    let text: String
    let isToday: Bool
    let isInCurrentMonth: Bool
    let date: Date?
    
    var events: [String] = []
    
    init(dto: USCalendarDayDataSource) {
        self.text = "\(dto.number)"
        self.isToday = dto.isToday
        self.isInCurrentMonth = dto.isInCurrentMonth
        self.date = dto.date
    }
}
