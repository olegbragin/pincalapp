//
//  PCCalendarMonthModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 01.02.2026.
//

import Foundation
import Observation

@Observable
final class PCCalendarMonthModel: Identifiable {
    let id: Int
    let label: String
    let number: Int
    let weekDaySymbols: [String]
    let weekHeaderModel: PCCalendarWeekHeaderModel
    let weeks: [PCCalendarWeekModel]
    
    var isLongPressed: Bool = false
        
    init(dto: PCCalendarMonthDataSource, daySelectionManager: PCCalendarDaySelectionManager) {
        self.id = dto.number
        self.label = dto.label
        self.number = dto.number
        self.weekDaySymbols = dto.weekDaySymbols
        self.weekHeaderModel = PCCalendarWeekHeaderModel(weekSymbols: dto.weekDaySymbols)
        self.weeks = dto.weeks.map {
            .init(dto: $0, daySelectionManager: daySelectionManager)
        }
    }
}

extension PCCalendarMonthModel: Equatable {
    static func == (lhs: PCCalendarMonthModel, rhs: PCCalendarMonthModel) -> Bool {
        lhs.id == rhs.id &&
        lhs.label == rhs.label &&
        lhs.number == rhs.number
    }
}

extension PCCalendarMonthModel: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(label)
        hasher.combine(number)
    }
}
