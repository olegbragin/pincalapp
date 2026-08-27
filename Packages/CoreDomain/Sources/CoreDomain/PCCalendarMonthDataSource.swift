//
//  PCCalendarMonthDataSource.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 23.03.2026.
//

public struct PCCalendarMonthDataSource {
    public let number: Int
    public let label: String
    public let weekDaySymbols: [String]
    public let weeks: [PCCalendarWeekDataSource]

    public init(number: Int, label: String, weekDaySymbols: [String], weeks: [PCCalendarWeekDataSource]) {
        self.number = number
        self.label = label
        self.weekDaySymbols = weekDaySymbols
        self.weeks = weeks
    }
}
