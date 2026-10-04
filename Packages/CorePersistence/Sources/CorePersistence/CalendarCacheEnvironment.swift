//
//  CalendarCacheEnvironment.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 05.09.2026.
//

import SwiftUI

public extension EnvironmentValues {
    /// The app-wide calendar cache. Injected once at the app root so views (and
    /// the view models they construct) can read it from `@Environment` instead
    /// of threading it through every initializer.
    @Entry var calendarCache: CalendarCache?
}
