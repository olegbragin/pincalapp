//
//  PCCalendarDayDataSource.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 01.02.2026.
//

import Foundation
import SwiftUI

public struct PCCalendarDayDataSource {
    public let date: Date
    public let number: Int
    public let isInCurrentMonth: Bool
    public let isToday: Bool
    
    public init(date: Date, number: Int, isInCurrentMonth: Bool, isToday: Bool) {
        self.date = date
        self.number = number
        self.isInCurrentMonth = isInCurrentMonth
        self.isToday = isToday
    }
}
