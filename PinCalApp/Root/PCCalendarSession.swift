//
//  PCCalendarSession.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 05.09.2026.
//

import SwiftUI
import CorePersistence
import CoreDomain
import SingleCalendarFeature

/// App-root session object. Bundles the app-wide dependencies that are shared
/// across calendars and injected into the models from `@Environment` through the
/// views, so they no longer have to be threaded through every initializer.
///
/// It owns the shared batch-editing managers, which are injected into
/// `SingleCalendarModel` and the batch views so all the participating models
/// communicate through them.
@MainActor
@Observable
final class PCCalendarSession {
    let cache: CalendarCache
    let dataProvider: PCCalendarDataProvider
    let daySelectionManager: PCCalendarDaySelectionManager
    let eventsSelectionManager: PCEventsSelectionManager

    init(
        cache: CalendarCache,
        dataProvider: PCCalendarDataProvider,
        daySelectionManager: PCCalendarDaySelectionManager,
        eventsSelectionManager: PCEventsSelectionManager
    ) {
        self.cache = cache
        self.dataProvider = dataProvider
        self.daySelectionManager = daySelectionManager
        self.eventsSelectionManager = eventsSelectionManager
    }
}
