//
//  USCalendarDayDataSource.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 01.02.2026.
//

import Foundation
import SwiftUI

struct USCalendarDayDataSource {
    let date: Date
    let number: Int
    let isInCurrentMonth: Bool
    let isToday: Bool
    
    init(date: Date, number: Int, isInCurrentMonth: Bool, isToday: Bool) {
        self.date = date
        self.number = number
        self.isInCurrentMonth = isInCurrentMonth
        self.isToday = isToday
    }
}
