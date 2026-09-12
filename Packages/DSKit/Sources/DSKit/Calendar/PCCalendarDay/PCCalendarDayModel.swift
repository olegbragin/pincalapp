//
//  PCCalendarDayModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 01.02.2026.
//

import Foundation
import Observation

@MainActor
@Observable
public final class PCCalendarDayModel: Identifiable {
    public let id = UUID()
    public let text: String
    public let isToday: Bool
    public let isInCurrentMonth: Bool
    public let date: Date?
    public let accessibilityID: String
    
    public var events: [String] = []
    
    var accessibilityLabel: String {
        guard !events.isEmpty else { return text }
        return "\(text), \(events.count) events"
    }
    
    var textColorRole: PCColorRole {
        switch (isToday, isInCurrentMonth) {
        case (true, _):
            return .foreground
        case (false, true):
            return events.isEmpty ? .foreground : .foregroundEvent
        case (false, false):
            return .foregroundDisabled
        }
    }
    
    var backgroundColorRole: PCColorRole {
        switch (isToday, isInCurrentMonth) {
        case (true, _), (false, true):
            return .background
        case (false, false):
            return .backgroundDisabled
        }
    }
    
    var borderColorRole: PCColorRole? {
        isToday ? .accent : nil
    }
    
    var fontRole: PCFontRole {
        isToday ? .todayDayNumber : .dayNumber
    }
    
    public init(date: Date, number: Int, isInCurrentMonth: Bool, isToday: Bool, gridMonth: Int) {
        self.text = "\(number)"
        self.isToday = isToday
        self.isInCurrentMonth = isInCurrentMonth
        self.date = date
        let dateString = Self.dayIDFormatter.string(from: date)
        self.accessibilityID = "day-\(String(format: "%02d", gridMonth))-\(dateString)"
    }
    
    private static let dayIDFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
