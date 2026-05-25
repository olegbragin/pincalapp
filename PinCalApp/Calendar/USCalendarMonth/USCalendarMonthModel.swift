//
//  USCalendarMonthModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 01.02.2026.
//

import Foundation
import Observation

@Observable
final class USCalendarMonthModel: Identifiable {
    let id: Int
    let label: String
    let number: Int
    let weekDaySymbols: [String]
    let weeks: [USCalendarWeekModel]
    
    var isLongPressed: Bool = false
        
    init(dto: USCalendarMonthDataSource, daySelectionManager: USCalendarDaySelectionManager) {
        self.id = dto.number
        self.label = dto.label
        self.number = dto.number
        self.weekDaySymbols = dto.weekDaySymbols
        self.weeks = dto.weeks.map {
            .init(dto: $0, daySelectionManager: daySelectionManager)
        }
    }
}

extension USCalendarMonthModel: Equatable {
    static func == (lhs: USCalendarMonthModel, rhs: USCalendarMonthModel) -> Bool {
        lhs.id == rhs.id &&
        lhs.label == rhs.label &&
        lhs.number == rhs.number
    }
}

extension USCalendarMonthModel: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(label)
        hasher.combine(number)
    }
}
