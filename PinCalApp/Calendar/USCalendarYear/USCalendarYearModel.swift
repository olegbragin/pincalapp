//
//  USCalendarYearModel.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 01.02.2026.
//

import SwiftUI

@Observable
final class USCalendarYearModel {
    
    enum ScrollDirection {
        case vertical
        case horizontal
    }
    
    // Для тактильной отдачи (опционально)
    private let hapticFeedback = UINotificationFeedbackGenerator()
    private(set) var internalNumberOfColumns: Int = 3
    
    var scrollDirection: ScrollDirection = .vertical
    
    var numberOfColumns: Int {
        didSet { internalNumberOfColumns = numberOfColumns }
    }
    var numberOfCurrentMonth: Int = 0
    var scrollPosition: CGFloat = 0
    
    var isLongPressEnabled: Bool = false
    
    var indexOfCurrentMonth: Int? {
        return months.firstIndex { $0.number == numberOfCurrentMonth }
    }

    var months: [USCalendarMonthModel] = []
    
    var monthRows: [[USCalendarMonthModel]] {
        let count = max(1, internalNumberOfColumns)
        guard !months.isEmpty else { return [] }
        return stride(from: 0, to: months.count, by: count).map { start in
            let end = min(start + count, months.count)
            return Array(months[start..<end])
        }
    }
    
    init(
        numberOfCurrentMonth: Int = 0,
        numberOfColumns: Int = 3,
        scrollDirection: ScrollDirection = .vertical
    ) {
        self.numberOfColumns = numberOfColumns
        self.numberOfCurrentMonth = numberOfCurrentMonth
        self.scrollDirection = scrollDirection
    }
    
    func set(initialNumberOfColumns: Int) {
        self.internalNumberOfColumns = initialNumberOfColumns
    }

    func reset() {
        numberOfColumns = internalNumberOfColumns
    }
}
