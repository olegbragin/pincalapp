//
//  PCCalendarWeekDataSource.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 01.02.2026.
//

import Foundation

public struct PCCalendarWeekDataSource {
    public let number: Int
    public let days: [PCCalendarDayDataSource]

    public init(number: Int, days: [PCCalendarDayDataSource]) {
        self.number = number
        self.days = days
    }
}
