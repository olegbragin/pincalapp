//
//  CalendarManagingEnvironment.swift
//  CalendarListFeature
//
//  Created by Oleg Bragin on 28.09.2026.
//

import SwiftUI
import CoreDomain

private struct CalendarManagingEnvironmentKey: EnvironmentKey {
    static let defaultValue: (any CalendarManaging)? = nil
}

extension EnvironmentValues {
    /// The calendar-management port, injected once at the app root.
    ///
    /// Replaces the `\.calendarCache` key this package used to read. The concrete
    /// `CalendarCache` lives in `CorePersistence` and is a DTO-speaking actor, so
    /// handing it to a feature module reopened the boundary requirement 4 closes. The
    /// port is domain-typed, and `CalendarListFeature` no longer imports
    /// `CorePersistence` at all.
    ///
    /// A value and not an environment *object*, deliberately: `.environment(_:)` needs
    /// an `Observable`, and `CalendarStore` is a stateless `nonisolated` struct with
    /// nothing to observe.
    public var calendarManaging: (any CalendarManaging)? {
        get { self[CalendarManagingEnvironmentKey.self] }
        set { self[CalendarManagingEnvironmentKey.self] = newValue }
    }
}
