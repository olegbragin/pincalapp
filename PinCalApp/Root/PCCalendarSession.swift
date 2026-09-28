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
import DSKit
import SingleCalendarFeature

/// App-root session object. Bundles the app-wide dependencies that are shared
/// across calendars and injected into the models from `@Environment` through the
/// views, so they no longer have to be threaded through every initializer.
///
/// It owns the shared batch-editing managers, which are injected into
/// `SingleCalendarModel` and the batch views so all the participating models
/// communicate through them.
///
/// It builds nothing. Every collaborator arrives through `init` — the port over the
/// calendar store, the data provider, the column-count resolver, and the two shared
/// managers — so a test can hand it whatever it needs. Its job is to hold them and
/// hand them to the rest of the app, not to decide what they are.
///
/// It holds no `CalendarCache`. The storage vocabulary stops here: consumers that need
/// the domain view ask for `persistence`, and consumers that genuinely need the cache
/// today — `SingleCalendarModel`, and `PCEventsSelectionManager` until it is replaced —
/// get it injected directly, because that dependency belongs to them rather than to the
/// session. `PCEventsSelectionManager` is the last cache consumer in the batch flow and
/// it goes in Stage 9, when `SingleCalendarModel` goes with it.
///
/// The storage/domain boundary is wired one level up, in `PinCalAppApp`, which is the
/// composition root. `CorePersistence` and `CoreDomain` do not depend on each other,
/// so the `CalendarStore` that joins them is constructed at the call site and handed in
/// here as `any CalendarPersisting`.
@MainActor
@Observable
final class PCCalendarSession {
    /// The domain-facing view of the calendar store. The batch pipeline is handed this
    /// and nothing else, so it cannot reach the `CalendarDataSource` DTOs.
    let persistence: any CalendarPersisting
    let dataProvider: PCCalendarDataProvider
    let columnCountResolver: (Int) -> Int
    let daySelectionManager: PCCalendarDaySelectionManager
    let eventsSelectionManager: PCEventsSelectionManager

    init(
        persistence: any CalendarPersisting,
        dataProvider: PCCalendarDataProvider = PCCalendarDataProvider(),
        columnCountResolver: @escaping (Int) -> Int = PCCalendarSession.makeColumnCountResolver(),
        daySelectionManager: PCCalendarDaySelectionManager,
        eventsSelectionManager: PCEventsSelectionManager
    ) {
        self.persistence = persistence
        self.dataProvider = dataProvider
        self.columnCountResolver = columnCountResolver
        self.daySelectionManager = daySelectionManager
        self.eventsSelectionManager = eventsSelectionManager
    }

    /// Resolves the year-grid column count. UI tests can force a specific count
    /// (e.g. a single column so the day cells are large and reliably tappable)
    /// via `-UITestColumns <n>`; otherwise the calendar's natural count is used.
    ///
    /// Used by the composition root to build the session's collaborators, so the
    /// override reaches the shared managers as well.
    static func makeColumnCountResolver() -> (Int) -> Int {
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
