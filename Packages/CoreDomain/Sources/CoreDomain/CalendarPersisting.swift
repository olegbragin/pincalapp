//
//  CalendarPersisting.swift
//  CoreDomain
//
//  Created by Oleg Bragin on 28.09.2026.
//

import Foundation

/// The data edge, seen from above.
///
/// `CalendarCache` in `CorePersistence` is the only thing in the app that talks to
/// ObjectBox, and it is also the only place that knows `PP*` entities, `*DataSource`
/// structs and `CalendarDataSource` exist. This protocol is declared here, in the
/// domain layer, so the feature layer can depend on the abstraction and never import
/// `CorePersistence`.
///
/// Three methods, and the split matters. A calendar's *management* data and its
/// *batches* are read by different consumers for different reasons, and
/// `CalendarListFeature` has no business holding an event graph it never reads. So
/// the calendar comes back as a `PinCalendar` — five scalars — and the batches come
/// back on their own.
///
/// Note what is *not* here: `CalendarCache.changes`. The selection manager does not
/// consume it, and `SingleCalendarModel` keeps its existing subscription to the
/// concrete cache for calendar metadata.
public protocol CalendarPersisting: Sendable {
    /// Reads a calendar's management data.
    func calendar(id: Int64) async throws -> PinCalendar?

    /// Reads the event batches assigned to a calendar.
    func eventBatches(calendarID: Int64) async throws -> [CalendarEventBatch]

    /// Writes the batch list and the column count.
    ///
    /// The store assigns ids. A caller never supplies one, and a batch with no
    /// `persistedID` must be written as new rather than as an update.
    func save(numberOfColumns: Int, eventBatches: [CalendarEventBatch], forCalendar id: Int64) async throws
}
