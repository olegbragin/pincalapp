//
//  PCCalendarWeekModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 28.01.2026.
//

import Foundation
import Observation

@MainActor
@Observable
public final class PCCalendarWeekModel: Identifiable {
    public let id = UUID()
    public let days: [PCCalendarDayModel]
    public let daySelectionManager: PCCalendarDaySelectionManager
    
    public init(days: [PCCalendarDayModel], daySelectionManager: PCCalendarDaySelectionManager) {
        self.daySelectionManager = daySelectionManager
        self.days = days
    }
    
    @MainActor
    public func select(day: PCCalendarDayModel) {
        daySelectionManager.select(day: day)
    }
}