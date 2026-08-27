//
//  PCCalendarDaySelectionManager.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 27.04.2026.
//

import Foundation
import CoreDomain
import Observation

@MainActor
@Observable
public final class PCCalendarDaySelectionManager {
    public var selectedDays: Set<Date> = []
    public var selectionMode: PCCalendarSelectionMode = .single

    public init() {}
    
    public func select(day: PCCalendarDayModel) {
        guard
            day.isInCurrentMonth,
            let selectedDay = day.date
        else { return }
        switch selectionMode {
        case .single:
            selectedDays.removeAll()
            selectedDays.insert(selectedDay)
        case .multiple:
            if !selectedDays.contains(selectedDay) {
                selectedDays.insert(selectedDay)
            } else {
                selectedDays.remove(selectedDay)
            }
        }
    }
    
    public func toggleSelectionMode() {
        let currentSelectionMode = selectionMode
        selectionMode = currentSelectionMode == .single ? .multiple : .single
    }
    
    public func reset() {
        selectedDays.removeAll()
        selectedDays = []
    }
}