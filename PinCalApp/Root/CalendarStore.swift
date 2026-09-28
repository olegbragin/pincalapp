//
//  CalendarStore.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 28.09.2026.
//

import Foundation
import CoreDomain
import CorePersistence

/// The concrete `CalendarPersisting`: the async read/write side of the storage edge.
///
/// `CalendarPersisting` is declared in `CoreDomain` so the feature layer can depend on
/// the abstraction. `CalendarCache` lives in `CorePersistence`, which must not depend
/// on `CoreDomain` — the storage layer should not know the domain vocabulary exists.
/// This is what joins them, and it is the only type that carries a `CalendarCache`.
///
/// It holds a cache and does I/O; all conversion between the two vocabularies is
/// delegated to an injected `EntityMappable`, which holds nothing. The split is
/// deliberate: the translation is pure and testable on its own, and this is the one
/// small, obviously-persistence type that talks to ObjectBox.
///
/// The app's composition root (`PinCalAppApp`) builds one and hands it to
/// `PCCalendarSession` as `any CalendarPersisting`. From that point the batch pipeline
/// cannot reach `CalendarCache` even by accident, which is what keeps
/// `SingleCalendarFeature` free of `import CorePersistence`.
///
/// A struct rather than a class: it holds `Sendable` references and no state of its
/// own, so it gets `Sendable` structurally and needs no `@unchecked`. `nonisolated`
/// because the app target defaults to MainActor isolation and the protocol's methods are
/// not main-actor-bound; the work happens off the main actor, where it belongs.
public nonisolated struct CalendarStore: CalendarPersisting {
    private let cache: CalendarCache
    private let mapper: any EntityMappable

    public init(cache: CalendarCache, mapper: any EntityMappable = RootMapper()) {
        self.cache = cache
        self.mapper = mapper
    }

    public func calendar(id: Int64) async throws -> PinCalendar? {
        guard let dto = try await cache.getCalendar(id: id) else { return nil }
        return mapper.calendar(from: dto)
    }

    public func eventBatches(calendarID: Int64) async throws -> [CalendarEventBatch] {
        guard let dto = try await cache.getCalendar(id: calendarID) else { return [] }
        return mapper.eventBatches(from: dto.eventBatches)
    }

    public func save(
        numberOfColumns: Int,
        eventBatches: [CalendarEventBatch],
        forCalendar id: Int64
    ) async throws {
        guard var dto = try await cache.getCalendar(id: id) else { return }
        dto.numberOfColumns = numberOfColumns
        dto.eventBatches = mapper.eventBatchDataSources(from: eventBatches)
        // Routed through `CalendarCache.updateCalendar`, which re-fetches and publishes
        // the change. That re-fetch is why a batch written with no `persistedID` comes
        // back with a real one, and the batch pipeline depends on it to recognise its
        // own staged row.
        try await cache.updateCalendar(dto)
    }
}
