//
//  PCCalendarYearDataSource.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 07.09.2026.
//

import Foundation

public struct PCCalendarYearDataSource {
    public let number: Int
    public let months: [PCCalendarMonthDataSource]

    public init(number: Int, months: [PCCalendarMonthDataSource]) {
        self.number = number
        self.months = months
    }
}
