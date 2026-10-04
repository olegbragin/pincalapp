//
//  PCFailedSave.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 01.10.2026.
//

import CoreDomain

/// A calendar write that did not land, held so it can be retried.
///
/// A value, not an event: the whole point is that the payload that failed is still available.
/// Retrying "the latest state" instead would paper over the failure — the next write for that
/// calendar already carries the current state, and would succeed, leaving this one silently
/// dropped. What has to survive is the specific write that failed.
public struct PCFailedSave: Equatable, Sendable {
    /// The calendar the failed write targeted.
    public let calendarID: Int64

    /// The column count that write carried, not the current one — replaying it must reproduce
    /// what failed rather than re-derive something newer.
    public let numberOfColumns: Int

    /// The batches exactly as they were offered, including the delete of anything absent from
    /// this set. Replaying a subset would resurrect rows the original write meant to remove.
    public let eventBatches: [CalendarEventBatch]

    /// User-facing text. Storage throws whatever ObjectBox throws, which is not something to
    /// show verbatim, so callers map it to something friendlier before display; this is the
    /// best available fallback.
    public let message: String

    public init(
        calendarID: Int64,
        numberOfColumns: Int,
        eventBatches: [CalendarEventBatch],
        message: String
    ) {
        self.calendarID = calendarID
        self.numberOfColumns = numberOfColumns
        self.eventBatches = eventBatches
        self.message = message
    }
}
