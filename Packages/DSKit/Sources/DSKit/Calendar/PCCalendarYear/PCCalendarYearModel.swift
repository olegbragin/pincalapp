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
    public private(set) var internalNumberOfColumns: Int = 3
    
    public var numberOfColumns: Int {
        didSet { internalNumberOfColumns = numberOfColumns }
    }
    
    public var maximumNumberOfColumns: Int = 3 {
        didSet {
            guard maximumNumberOfColumns != oldValue else { return }
            let clamped = min(internalNumberOfColumns, maximumNumberOfColumns)
            if clamped != internalNumberOfColumns {
                numberOfColumns = clamped
            }
        }
    }
    
    public var numberOfCurrentMonth: Int = 0
    /// The month (1...12) the calendar should scroll to. Set by the feature layer,
    /// which owns the calendar/date logic; the view just reads `targetMonthIndex`.
    public var scrollTargetMonth: Int?
    public var scrollPosition: CGFloat = 0
    
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

    public func set(initialNumberOfColumns: Int) {
        self.numberOfColumns = initialNumberOfColumns
    }

    public func reset() {
        numberOfColumns = internalNumberOfColumns
    }
}
