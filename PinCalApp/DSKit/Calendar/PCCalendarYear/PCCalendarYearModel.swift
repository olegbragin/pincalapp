//
//  USCalendarYearModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 01.02.2026.
//

import SwiftUI

@Observable
final class USCalendarYearModel {
    
    // Для тактильной отдачи (опционально)
    private let hapticFeedback = UINotificationFeedbackGenerator()
    private(set) var internalNumberOfColumns: Int = 3
    
    var numberOfColumns: Int {
        didSet { internalNumberOfColumns = numberOfColumns }
    }
    var maximumNumberOfColumns: Int = 3 {
        didSet {
            guard maximumNumberOfColumns != oldValue else { return }
            let clamped = min(internalNumberOfColumns, maximumNumberOfColumns)
            if clamped != internalNumberOfColumns {
                numberOfColumns = clamped
            }
        }
    }
    var numberOfCurrentMonth: Int = 0
    var scrollTargetDate: Date?
    var scrollPosition: CGFloat = 0
    
    var isLongPressEnabled: Bool = false
    
    var indexOfCurrentMonth: Int? {
        return months.firstIndex { $0.number == numberOfCurrentMonth }
    }

    var months: [USCalendarMonthModel] = []
    
    init(
        numberOfCurrentMonth: Int = 0,
        numberOfColumns: Int = 3
    ) {
        self.numberOfColumns = numberOfColumns
        self.numberOfCurrentMonth = numberOfCurrentMonth
    }
    
    func set(initialNumberOfColumns: Int) {
        self.numberOfColumns = initialNumberOfColumns
    }

    func reset() {
        numberOfColumns = internalNumberOfColumns
    }
}
