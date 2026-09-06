//
//  PCCalendarSession.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 05.09.2026.
//

import Foundation
import Observation
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

    init(cache: CalendarCache) {
        self.cache = cache
        let dataProvider = PCCalendarDataProvider(columnCountResolver: Self.makeColumnCountResolver())
        self.dataProvider = dataProvider
        let daySelectionManager = PCCalendarDaySelectionManager()
        self.daySelectionManager = daySelectionManager
        self.eventsSelectionManager = PCEventsSelectionManager(
            cache: cache,
            dataProvider: dataProvider,
            daySelectionManager: daySelectionManager
        )
    }

    /// Resolves the year-grid column count. UI tests can force a specific count
    /// (e.g. a single column so the day cells are large and reliably tappable)
    /// via `-UITestColumns <n>`; otherwise the calendar's natural count is used.
    private static func makeColumnCountResolver() -> (Int) -> Int {
        { requested in forcedColumnsForUITests ?? requested }
    }

    private static var forcedColumnsForUITests: Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let flagIndex = arguments.firstIndex(of: "-UITestColumns"),
            arguments.indices.contains(flagIndex + 1),
            let value = Int(arguments[flagIndex + 1])
        else { return nil }
        return value
    }
}
