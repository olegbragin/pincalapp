//
//  CalendarManagingEnvironment.swift
//  CalendarListFeature
//
//  Created by Oleg Bragin on 28.09.2026.
//

import SwiftUI
import CoreDomain

public extension EnvironmentValues {
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
    @Entry var calendarManaging: (any CalendarManaging)?
}
