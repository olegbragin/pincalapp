//
//  PCCalendarYearModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 01.02.2026.
//

import Foundation
import Observation
import CoreGraphics

@MainActor
@Observable
public final class PCCalendarYearModel {
    public var numberOfColumns: Int = 3
    
    public var maximumNumberOfColumns: Int = 3 {
        didSet {
            guard maximumNumberOfColumns != oldValue else { return }
            let clamped = min(numberOfColumns, maximumNumberOfColumns)
            if clamped != numberOfColumns {
                numberOfColumns = clamped
            }
        }
    }
    
    public var numberOfCurrentMonth: Int = 0
    /// The month (1...12) the calendar should scroll to. Set by the feature layer,
    /// which owns the calendar/date logic; the view just reads `targetMonthIndex`.
    public var scrollTargetMonth: Int?
    
    public var indexOfCurrentMonth: Int? {
        return months.firstIndex { $0.number == numberOfCurrentMonth }
    }

    /// The index of the month to scroll to: the explicitly-set target month, or
    /// the current month when none is set.
    public var targetMonthIndex: Int? {
        if let scrollTargetMonth {
            return months.firstIndex { $0.number == scrollTargetMonth }
        }
        return indexOfCurrentMonth
    }

    public var months: [PCCalendarMonthModel] = []
    
    public init(
        numberOfCurrentMonth: Int = 0,
        numberOfColumns: Int = 3
    ) {
        self.numberOfColumns = numberOfColumns
        self.numberOfCurrentMonth = numberOfCurrentMonth
    }
}
