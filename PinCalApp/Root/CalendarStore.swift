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
public nonisolated struct CalendarStore: CalendarPersisting, CalendarManaging {
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
        // Fault injection, so the save-failure path is reachable from a UI test.
        //
        // That path is the one that decides whether a user loses work: a failure blocks the
        // calendar switch and raises a toast with Retry, and none of that is testable while
        // the only way to fail a save is to fill the disk. `-UITestFailSaves` makes every
        // write throw, so a test can drive the real user-visible path — toast, button,
        // blocked switch — rather than a stand-in for it.
        if ProcessInfo.processInfo.arguments.contains("-UITestFailSaves") {
            throw URLError(.cannotWriteToFile)
        }
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

// MARK: - CalendarManaging

extension CalendarStore {

    /// Bridges the cache's DTO-typed feed into the domain feed, translating each
    /// operation as it arrives.
    ///
    /// Stateless on purpose: the subscriber's own task drives the bridge, so there is no
    /// continuation bookkeeping here and no state to keep in sync. Whoever asks for the
    /// stream owns it for as long as they iterate.
    public nonisolated func changes() async -> AsyncStream<PinCalendarChange> {
        let cache = cache
        let mapper = mapper
        // Awaited out here rather than inside the builder closure: `cache.changes()`
        // reaches into an actor, and the builder body is synchronous. Taking the
        // subscription before building the bridged stream also means it is already live
        // by the time this returns, so no change published in between is dropped.
        let upstream = await cache.changes()
        return AsyncStream { continuation in
            let task = Task {
                for await operation in upstream {
                    guard let change = Self.change(from: operation, using: mapper) else { continue }
                    continuation.yield(change)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private nonisolated static func change(
        from operation: ChangeOperation,
        using mapper: any EntityMappable
    ) -> PinCalendarChange? {
        switch operation {
        case .add(let dto): return .added(mapper.calendar(from: dto))
        case .delete(let dto): return .removed(mapper.calendar(from: dto))
        case .change(let dto): return .changed(mapper.calendar(from: dto))
        case .refresh(let dtos): return .refreshed(dtos.map(mapper.calendar(from:)))
        }
    }

    public nonisolated func loadActive() async -> [PinCalendar] {
        await cache.loadActive()
        return await calendarSnapshot()
    }

    public nonisolated func loadArchived() async -> [PinCalendar] {
        await cache.loadArchived()
        return await calendarSnapshot()
    }

    public nonisolated func createCalendar(name: String, year: Int, numberOfColumns: Int) async throws {
        try await cache.createCalendar(name: name, year: year, numberOfColumns: numberOfColumns)
    }

    /// Renames / re-lays-out a calendar, field by field.
    ///
    /// Deliberately **not** a whole-`PinCalendar` overwrite: `PinCalendar` carries no
    /// event graph, so mapping one back onto the DTO wholesale would write an empty
    /// `eventBatches` and delete every batch on the calendar. The DTO is re-read and
    /// only the five management fields are touched, leaving the relation alone.
    public nonisolated func updateCalendar(_ calendar: PinCalendar) async throws {
        guard var dto = try await cache.getCalendar(id: calendar.id) else { return }
        dto.name = calendar.name
        dto.year = calendar.year
        dto.numberOfColumns = calendar.numberOfColumns
        dto.isArchived = calendar.isArchived
        try await cache.updateCalendar(dto)
    }

    public nonisolated func archiveCalendar(id: Int64) async throws {
        guard let dto = try await cache.getCalendar(id: id) else { return }
        try await cache.archiveCalendar(dto)
    }

    public nonisolated func restoreCalendar(id: Int64) async throws {
        guard let dto = try await cache.getCalendar(id: id) else { return }
        try await cache.restoreCalendar(dto)
    }

    public nonisolated func permanentlyDeleteCalendar(id: Int64) async throws {
        guard let dto = try await cache.getCalendar(id: id) else { return }
        try await cache.permanentlyDeleteCalendar(dto)
    }

    private nonisolated func calendarSnapshot() async -> [PinCalendar] {
        await cache.loadedCalendars().map(mapper.calendar(from:))
    }
}
