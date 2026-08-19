//
//  PCCalendarDayModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 01.02.2026.
//

import Foundation

@Observable
final class PCCalendarDayModel: Identifiable {
    let id = UUID()
    let text: String
    let isToday: Bool
    let isInCurrentMonth: Bool
    let date: Date?
    let accessibilityID: String
    
    var events: [String] = []
    
    init(dto: PCCalendarDayDataSource) {
        self.text = "\(dto.number)"
        self.isToday = dto.isToday
        self.isInCurrentMonth = dto.isInCurrentMonth
        self.date = dto.date
        self.accessibilityID = "day-\(Self.dayIDFormatter.string(from: dto.date))"
    }
    
    private static let dayIDFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
