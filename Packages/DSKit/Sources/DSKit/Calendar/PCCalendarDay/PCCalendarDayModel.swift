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