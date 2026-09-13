//
//  PCCalendarYearDataSource.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 07.09.2026.
//

import Foundation

public struct PCCalendarYearDataSource {
    public let year: Int
    public let months: [PCCalendarMonthDataSource]

    public init(year: Int, months: [PCCalendarMonthDataSource]) {
        self.year = year
        self.months = months
    }
}
