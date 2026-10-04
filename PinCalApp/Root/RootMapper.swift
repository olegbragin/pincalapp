//
//  RootMapper.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 28.09.2026.
//

import Foundation
import CoreDomain
import CorePersistence

/// The production `EntityMappable`. Translates the root calendar entity and everything
/// beneath it.
///
/// Stateless: it holds nothing, does no I/O, and depends on nothing but the two type
/// families it converts. Injecting it rather than calling statics is what lets a test
/// substitute the translation — see `EntityMappable`.
///
/// The mapping runs against the DTOs rather than the `PP*` entities on purpose. The
/// DTOs already carry exactly the same information, so mapping at this level lets
/// `CalendarStore` reuse `CalendarCache.updateCalendar` — the existing, tested write
/// path, including the re-fetch that lets the store hand back the ids it assigned —
/// instead of duplicating it. Nothing here touches ObjectBox.
///
/// Opts out of the app target's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
/// Value-to-value conversion has no shared state and no business on the main actor.
public nonisolated struct RootMapper: EntityMappable {
    public init() {}

    // MARK: - DTO -> domain

    public func calendar(from dto: CalendarDataSource) -> PinCalendar {
        PinCalendar(
            id: dto.id,
            name: dto.name,
            year: dto.year,
            numberOfColumns: dto.numberOfColumns,
            isArchived: dto.isArchived
        )
    }

    public func event(from dto: EventDataSource) -> CalendarEvent {
        CalendarEvent(
            persistedID: dto.id == 0 ? nil : dto.id,
            name: dto.name,
            date: dto.date,
            colorName: dto.color
        )
    }

    public func eventBatch(from dto: EventBatchDataSource) -> CalendarEventBatch {
        CalendarEventBatch(
            persistedID: dto.id == 0 ? nil : dto.id,
            name: dto.name,
            colorName: dto.colorName,
            events: dto.events.map(event(from:))
        )
    }

    public func eventBatches(from dtos: [EventBatchDataSource]) -> [CalendarEventBatch] {
        dtos.map(eventBatch(from:))
    }

    // MARK: - domain -> DTO

    public func eventDataSource(from event: CalendarEvent) -> EventDataSource {
        EventDataSource(
            id: event.persistedID ?? 0,
            name: event.name,
            date: event.date,
            color: event.colorName
        )
    }

    public func eventBatchDataSource(from batch: CalendarEventBatch) -> EventBatchDataSource {
        EventBatchDataSource(
            id: batch.persistedID ?? 0,
            name: batch.name,
            colorName: batch.colorName,
            events: batch.events.map(eventDataSource(from:)),
            date: batch.date
        )
    }

    public func eventBatchDataSources(from batches: [CalendarEventBatch]) -> [EventBatchDataSource] {
        batches.map(eventBatchDataSource(from:))
    }
}
