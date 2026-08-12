//
//  USCalendarWeekModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 28.01.2026.
//

import Foundation
import SwiftUI

@Observable
final class USCalendarWeekModel: Identifiable {
    let id = UUID()
    let days: [USCalendarDayModel]
    let daySelectionManager: USCalendarDaySelectionManager
    
    var isLongPressed: Bool = false
    
    init(dto: USCalendarWeekDataSource, daySelectionManager: USCalendarDaySelectionManager) {
        self.daySelectionManager = daySelectionManager
        self.days = dto.days.map {
            USCalendarDayModel(dto: $0)
        }
    }
    
    func select(day: USCalendarDayModel) {
        daySelectionManager.select(day: day)
    }
}
