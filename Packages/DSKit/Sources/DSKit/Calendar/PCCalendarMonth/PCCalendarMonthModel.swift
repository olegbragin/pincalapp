//
//  PCCalendarMonthModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 01.02.2026.
//

import Foundation
import CoreDomain
import Observation

@MainActor
@Observable
public final class PCCalendarMonthModel: Identifiable {
    public let id: Int
    public let label: String
    public let number: Int
    public let weekDaySymbols: [String]
    public let weekHeaderModel: PCCalendarWeekHeaderModel
    public let weeks: [PCCalendarWeekModel]
    
    public var isLongPressed: Bool = false
        
    public init(dto: PCCalendarMonthDataSource, daySelectionManager: PCCalendarDaySelectionManager) {
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
    public static func == (lhs: PCCalendarMonthModel, rhs: PCCalendarMonthModel) -> Bool {
        lhs.id == rhs.id &&
        lhs.label == rhs.label &&
        lhs.number == rhs.number
    }
}

extension PCCalendarMonthModel: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(label)
        hasher.combine(number)
    }
}