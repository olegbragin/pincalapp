//
//  EntityMappable.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 28.09.2026.
//

import Foundation
import CoreDomain
import CorePersistence

/// Translating between the two entity vocabularies.
///
/// `EventDataSource`, `EventBatchDataSource` and `CalendarDataSource` are the storage
/// layer's own projection of the `PP*` entities and stay in `CorePersistence`;
/// `CalendarEvent`, `CalendarEventBatch` and `PinCalendar` are what the app speaks.
/// `CorePersistence` and `CoreDomain` do not depend on each other, so this protocol
/// can only live where both are visible — the app target — and it is the seam that
/// lets a caller substitute the translation.
///
/// One responsibility, seven functions, so there is one protocol rather than three.
/// Splitting it per entity would buy interface segregation nobody needs for a set of
/// pure functions, at the cost of three types to pass around.
///
/// `RootMapper` is the production implementation. It is a dependency rather than a
/// static namespace so a test can put a different translation in its place — for
/// instance one that normalises colour names, or one that drops persisted ids, neither
/// of which the real mapping would ever do.
///
/// `nonisolated`, like its implementors: the app target sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which would otherwise bind these
/// requirements to the main actor and make the protocol unusable from
/// `CalendarPersisting`'s nonisolated methods.
public nonisolated protocol EntityMappable: Sendable {

    // MARK: - DTO -> domain

    func calendar(from dto: CalendarDataSource) -> PinCalendar
    func event(from dto: EventDataSource) -> CalendarEvent
    func eventBatch(from dto: EventBatchDataSource) -> CalendarEventBatch
    func eventBatches(from dtos: [EventBatchDataSource]) -> [CalendarEventBatch]

    // MARK: - domain -> DTO

    func eventDataSource(from event: CalendarEvent) -> EventDataSource
    func eventBatchDataSource(from batch: CalendarEventBatch) -> EventBatchDataSource
    func eventBatchDataSources(from batches: [CalendarEventBatch]) -> [EventBatchDataSource]
}
