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
    ///
    /// ### The staged batch replaces its committed row; it does not join it
    ///
    /// Staging is not always *creating*. An assembly opened from the registry with
    /// `existing(_:)` is that very row, still holding its committed `persistedID`, and a
    /// marker is about what the batch holds *now* — which is the staged copy. Appending
    /// the two, which is what this used to do, was wrong twice over:
    ///
    /// - an event deleted from the staged copy kept painting its marker, because the
    ///   committed copy still listed it. Removing the last event of a day left that day
    ///   marked forever, and no amount of re-projecting could clear it — the payload was
    ///   wrong, not the projection.
    /// - a day both copies held was counted twice, so a batch with one event on a day was
    ///   labelled with two.
    ///
    /// So the staged row *replaces* the committed row that shares its `mergeKey`, and is
    /// appended only when no such row exists — which is the genuinely-new case, where the
    /// keys cannot match (§5.4.1).
    ///
    /// ### `multiSelect` — the one part of the payload that is not a batch yet
    ///
    /// A multi-select session is days and a colour with no row anywhere: it only becomes a
    /// batch when the user confirms it. Without it in the payload, tapping a day in a
    /// session produced *no visible change at all* — the day was recorded, the toolbar's
    /// Save would act on it, and the calendar looked untouched. The only feedback a tap
    /// gave was the colour picker greying out, which reads as the picker reacting rather
    /// than the calendar responding, and that is exactly how the bug was reported.
    ///
    /// Projected last, but only for days the batches did not already paint — see the comment
    /// at the append. The session is what the user is looking at and it overrides nothing
    /// already committed.
    nonisolated static func colorsByDay(
        from batches: [CalendarEventBatch],
        includingStaged staged: PCEventBatchAssembleUnitOfWork?,
        multiSelect: (days: [Date], colorName: String)? = nil,
        using dataProvider: PCCalendarDataProvider
    ) -> [Date: [String]] {
        let effective: [CalendarEventBatch]
        if let staged {
            let key = staged.mergeKey
            effective = batches.contains { $0.mergeKey == key }
                ? batches.map { $0.mergeKey == key ? staged.batch : $0 }
                : batches + [staged.batch]
        } else {
            effective = batches
        }

        var result: [Date: [String]] = [:]
        for batch in effective {
            for event in batch.events {
                result[dataProvider.startOfDay(for: event.date), default: []].append(event.colorName)
            }
        }
        if let multiSelect {
            for day in multiSelect.days {
                let key = dataProvider.startOfDay(for: day)
                // Replaces rather than appends, for the same reason the staged row does
                // above: "one batch on a day is labelled with two" is a bug, and a session
                // day stopped being a special case the moment the first tap wrote it.
                //
                // It used to be one. The reasoning here was that a session is days and a
                // colour with no row anywhere, true while confirming was what committed it,
                // and not true once every tap merged into `batches` — which is what removed
                // the need for a confirm step at all. From the first tap the session's days
                // are committed rows, so appending painted every selected day a second time,
                // and `PCCalendarDayEventView` draws one band per entry: each selected day
                // was split between two copies of its own colour instead of filled with it.
                if result[key]?.isEmpty ?? true {
                    result[key, default: []].append(multiSelect.colorName)
                }
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
