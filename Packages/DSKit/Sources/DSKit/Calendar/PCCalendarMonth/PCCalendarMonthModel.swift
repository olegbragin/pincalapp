//
//  PCCalendarMonthModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 01.02.2026.
//

import Foundation
import Observation

@MainActor
@Observable
public final class PCCalendarMonthModel: Identifiable {
    public nonisolated let id: Int
    public nonisolated let label: String
    public nonisolated let number: Int
    public let weekDaySymbols: [String]
    public let weekHeaderModel: PCCalendarWeekHeaderModel
    public let weeks: [PCCalendarWeekModel]
    
    public init(number: Int, label: String, weekDaySymbols: [String], weeks: [PCCalendarWeekModel]) {
        self.id = number
        self.label = label
        self.number = number
        self.weekDaySymbols = weekDaySymbols
        self.weekHeaderModel = PCCalendarWeekHeaderModel(weekSymbols: weekDaySymbols)
        self.weeks = weeks
    }
}

extension PCCalendarMonthModel: Equatable {
    nonisolated public static func == (lhs: PCCalendarMonthModel, rhs: PCCalendarMonthModel) -> Bool {
        lhs.id == rhs.id &&
        lhs.label == rhs.label &&
        lhs.number == rhs.number
    }
}

extension PCCalendarMonthModel: Hashable {
    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(label)
        hasher.combine(number)
    }
}