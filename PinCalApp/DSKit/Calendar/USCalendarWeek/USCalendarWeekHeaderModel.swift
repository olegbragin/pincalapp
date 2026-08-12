//
//  USCalendarWeekHeaderModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 28.01.2026.
//

import Foundation
import Observation

@Observable
final class USCalendarWeekHeaderModel {
    struct WeekSymbol: Identifiable {
        let id = UUID()
        let name: String
    }
    
    let weekSymbols: [WeekSymbol]
    
    init(weekSymbols: [String]) {
        self.weekSymbols = weekSymbols.map {
            WeekSymbol(name: $0)
        }
    }
}
