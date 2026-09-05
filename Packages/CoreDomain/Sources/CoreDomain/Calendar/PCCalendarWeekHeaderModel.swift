//
//  PCCalendarWeekHeaderModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 28.01.2026.
//

import Foundation
import Observation

@MainActor
@Observable
public final class PCCalendarWeekHeaderModel {
    public struct WeekSymbol: Identifiable {
        public let id: UUID
        public let name: String
        public init(id: UUID = UUID(), name: String) { self.id = id; self.name = name }
    }
    
    public let weekSymbols: [WeekSymbol]
    
    public init(weekSymbols: [String]) {
        self.weekSymbols = weekSymbols.map {
            WeekSymbol(name: $0)
        }
    }
}