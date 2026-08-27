//
//  PCCalendarWeekModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 28.01.2026.
//

import Foundation
import SwiftUI
import CoreDomain

@MainActor
@Observable
public final class PCCalendarWeekModel: Identifiable {
    public let id = UUID()
    public let days: [PCCalendarDayModel]
    public let daySelectionManager: PCCalendarDaySelectionManager
    
    public var isLongPressed: Bool = false
    
    public init(dto: PCCalendarWeekDataSource, daySelectionManager: PCCalendarDaySelectionManager) {
        self.daySelectionManager = daySelectionManager
        self.days = dto.days.map {
            PCCalendarDayModel(dto: $0)
        }
    }
    
    @MainActor
    public func select(day: PCCalendarDayModel) {
        daySelectionManager.select(day: day)
    }
}