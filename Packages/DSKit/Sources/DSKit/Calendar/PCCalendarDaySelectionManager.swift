//
//  PCCalendarDaySelectionManager.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 27.04.2026.
//

import Foundation
import Observation

@MainActor
@Observable
public final class PCCalendarDaySelectionManager {
    public var selectedDays: Set<Date> = []
    public var selectionMode: PCCalendarSelectionMode = .single

    /// The single listener for a day tap on this manager.
    ///
    /// `selectedDays` used to be the whole message bus: screens observed the set with
    /// `onChange` and inferred intent from it. That is the failure mode this callback
    /// exists to remove — with a set as the channel, seeding it (to preselect the days of
    /// an opened batch) is indistinguishable from the user tapping them, which is why
    /// `PCEventsSelectionManager.prepare(with:)` has to defensively clear the set, and why
    /// two observers can disagree about the same tap. A tap is reported as a tap.
    ///
    /// Installed by the visible screen and cleared on its disappearance, so exactly one
    /// screen is listening at a time. `nil` when nothing is.
    public var onDayTapped: ((Date) -> Void)?

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
        onDayTapped?(selectedDay)
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
