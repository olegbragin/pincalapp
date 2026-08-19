//
//  PCCalendarWeekModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 28.01.2026.
//

import Foundation
import SwiftUI

@Observable
final class PCCalendarWeekModel: Identifiable {
    let id = UUID()
    let days: [PCCalendarDayModel]
    let daySelectionManager: PCCalendarDaySelectionManager
    
    var isLongPressed: Bool = false
    
    init(dto: PCCalendarWeekDataSource, daySelectionManager: PCCalendarDaySelectionManager) {
        self.daySelectionManager = daySelectionManager
        self.days = dto.days.map {
            PCCalendarDayModel(dto: $0)
        }
    }
    
    func select(day: PCCalendarDayModel) {
        daySelectionManager.select(day: day)
    }
}
