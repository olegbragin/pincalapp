//
//  PCCalendarMarkerProjector.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 28.09.2026.
//

import Foundation
import CoreDomain
import DSKit

/// The day-marker projection, in one place.
///
/// This used to exist twice, near-identically: `PCEventsSelectionManager.updateYearModel`
/// / `eventColorsByDay` and `SingleCalendarModel.updateYearModel` /
/// `colorsByStartOfDay`, plus a third linear day scan in `SingleCalendarModel.dayModel(for:)`
/// that existed only to serve a single-day fast path. Two copies of a projection is two
/// places for the calendar to disagree with itself.
@MainActor
enum PCCalendarMarkerProjector {

    /// start-of-day → the colour names of the events on that day, in batch order.
    nonisolated static func colorsByDay(
        from batches: [CalendarEventBatch],
        using dataProvider: PCCalendarDataProvider
    ) -> [Date: [String]] {
        colorsByDay(from: batches, includingStaged: nil, using: dataProvider)
    }

    /// The same, with the in-flight assembly folded in.
    ///
    /// The staged batch is not in `batches` — that is the whole point of staging it — so
    /// the committed set alone cannot describe what the editor's calendar should show. If
    /// the assembly recolours or toggles a day, its colours are the ones the user is
    /// looking at, and the markers have to follow.
    nonisolated static func colorsByDay(
        from batches: [CalendarEventBatch],
        includingStaged staged: BatchAssembler?,
        using dataProvider: PCCalendarDataProvider
    ) -> [Date: [String]] {
        var result: [Date: [String]] = [:]
        for batch in batches + (staged.map { [$0.batch] } ?? []) {
            for event in batch.events {
                result[dataProvider.startOfDay(for: event.date), default: []].append(event.colorName)
            }
        }
        return result
    }

    /// Writes the marker payload into a built year model.
    ///
    /// Mutates each day model's `events` in place rather than rebuilding the matrix. A
    /// rebuild per action would hand the views fresh day-model instances, and
    /// `PCCalendarYearModel.months` — where the views bind — would stop tracking them, so
    /// the calendar would silently stop updating. The `guard` avoids even the in-place
    /// write when nothing changed, because that write is observable too.
    static func apply(
        _ colorsByDay: [Date: [String]],
        to yearModel: PCCalendarYearModel,
        using dataProvider: PCCalendarDataProvider
    ) {
        for month in yearModel.months {
            for week in month.weeks {
                for day in week.days where day.isInCurrentMonth {
                    guard let dayDate = day.date else { continue }
                    let colors = colorsByDay[dataProvider.startOfDay(for: dayDate)] ?? []
                    guard day.events != colors else { continue }
                    day.events = colors
                }
            }
        }
    }
}
