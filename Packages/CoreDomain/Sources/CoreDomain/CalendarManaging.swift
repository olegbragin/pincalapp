//
//  CalendarManaging.swift
//  CoreDomain
//
//  Created by Oleg Bragin on 28.09.2026.
//

import Foundation

/// A calendar-list change, in domain terms.
///
/// The storage layer has its own `ChangeOperation` carrying `CalendarDataSource`. This
/// is the same information expressed in the vocabulary the app speaks, so the calendar
/// list never has to name a DTO to react to a change.
public enum PinCalendarChange: Equatable, Sendable {
    case added(PinCalendar)
    case removed(PinCalendar)
    case changed(PinCalendar)
    case refreshed([PinCalendar])
}

/// Calendar management: the operations the calendar-list screen performs.
///
/// Distinct from `CalendarPersisting`, which is the batch pipeline's much narrower
/// port. This one covers the list — load, create, rename, archive, restore, delete —
/// and carries the change feed the list reacts to.
///
/// Two deliberate choices:
///
/// - **`loadActive()` / `loadArchived()` return what they loaded.** The list used to
///   call a `Void` load and then wait for the `.refresh` broadcast that call emitted.
///   A push feed has no replay, and the subscription may not be live yet, so a first
///   paint that awaited its own echo intermittently came up empty. Returning the result
///   makes that mistake unrepresentable.
/// - **`changes()` is a method, not a property.** `AsyncStream` is single-consumer, so
///   each call is a fresh subscription; naming it `changes()` says so. It is `async`
///   because registering a subscriber reaches into the cache actor.
public protocol CalendarManaging: Sendable {
    /// A fresh change stream. One per call, one consumer each.
    func changes() async -> AsyncStream<PinCalendarChange>

    /// Loads the active calendars and returns them.
    func loadActive() async -> [PinCalendar]

    /// Loads the archived calendars and returns them.
    func loadArchived() async -> [PinCalendar]

    func createCalendar(name: String, year: Int, numberOfColumns: Int) async throws
    func updateCalendar(_ calendar: PinCalendar) async throws
    func archiveCalendar(id: Int64) async throws
    func restoreCalendar(id: Int64) async throws
    func permanentlyDeleteCalendar(id: Int64) async throws
}
