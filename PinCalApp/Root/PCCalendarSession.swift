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
/// It owns the batch-assembly store, which every screen in the flow reads and dispatches
/// through. This is the only file in the app that names both `CalendarCache` and
/// `PCEventSelectionManager`: the former is storage, the latter is the domain-facing
/// feature, and the only place the two are allowed to meet is the composition root.
///
/// It builds nothing. Every collaborator arrives through `init` — the port over the
/// calendar store, the data provider, the column-count resolver, and the two shared
/// managers — so a test can hand it whatever it needs. Its job is to hold them and
/// hand them to the rest of the app, not to decide what they are.
///
/// It holds no `CalendarCache`. The storage vocabulary stops here: consumers that need
/// the domain view ask for `persistence`, and the one consumer that genuinely needed the
/// cache — `SingleCalendarModel`, for the calendar's metadata feed — now asks
/// `managing` for it instead and took `import CorePersistence` with it in Stage 9.
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
    /// Calendar *management*: the metadata change feed, alongside the list's own
    /// load/create/archive operations. `SingleCalendarModel` follows this calendar's name,
    /// year, archived flag and column count, which are not batch state — so they do not
    /// belong on the batch port — and are not storage, so the model does not need a cache.
    /// This is what let `SingleCalendarFeature` drop `CorePersistence` in Stage 9.
    let managing: any CalendarManaging
    let dataProvider: PCCalendarDataProvider
    let columnCountResolver: (Int) -> Int
    /// The main calendar panel's day-selection manager. Deliberately *not* the store's:
    /// the store owns the batch editor's, and sharing one is what let the editor's
    /// selection mode leak onto the screen behind it.
    let daySelectionManager: PCCalendarDaySelectionManager
    let eventSelection: PCEventSelectionManager

    init(
        persistence: any CalendarPersisting,
        managing: any CalendarManaging,
        eventSelection: PCEventSelectionManager,
        dataProvider: PCCalendarDataProvider = PCCalendarDataProvider(),
        columnCountResolver: @escaping (Int) -> Int = PCCalendarSession.makeColumnCountResolver(),
        daySelectionManager: PCCalendarDaySelectionManager
    ) {
        self.persistence = persistence
        self.managing = managing
        self.eventSelection = eventSelection
        self.dataProvider = dataProvider
        self.columnCountResolver = columnCountResolver
        self.daySelectionManager = daySelectionManager
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
