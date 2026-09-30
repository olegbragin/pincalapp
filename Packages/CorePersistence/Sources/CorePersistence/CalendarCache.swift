//
//  CalendarCache.swift
//  PinCalApp
//

import Foundation

public enum ChangeOperation: Sendable {
    case add(item: CalendarDataSource)
    case delete(item: CalendarDataSource)
    case change(item: CalendarDataSource)
    case refresh(calendars: [CalendarDataSource])
}

/// In-memory calendar list plus a change feed.
///
/// The feed was a Combine `PassthroughSubject` and is now an `AsyncStream`
/// fan-out. Two things change beyond the type. First, `AsyncStream` is
/// single-consumer where a subject is shared, so each caller gets its own stream and
/// the cache holds a continuation per subscriber — there are at most two live ones, the
/// calendar list and one calendar detail. Second, the senders no longer hop to the main
/// actor to deliver: yielding from inside the actor is already correctly isolated, so
/// the `MainActor.run` detour is gone.
public actor CalendarCache {
    private var calendars: [CalendarDataSource] = []
    private var changeContinuations: [UUID: AsyncStream<ChangeOperation>.Continuation] = [:]

    private let repository: any CalendarRepository

    public init(repository: any CalendarRepository) {
        self.repository = repository
    }

    /// A fresh change stream, registered before this returns.
    ///
    /// A method rather than a property because registration touches actor state, so it
    /// has to happen inside the actor. Await it *before* triggering whatever you are
    /// waiting to hear about: the stream buffers from the moment of registration, so an
    /// action fired earlier can still be missed.
    public func changes() -> AsyncStream<ChangeOperation> {
        let id = UUID()
        return AsyncStream { continuation in
            changeContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        changeContinuations[id] = nil
    }

    private func broadcast(_ operation: ChangeOperation) {
        for continuation in changeContinuations.values {
            continuation.yield(operation)
        }
    }

    public func loadActive() async {
        let fetched = try? await repository.getActiveCalendars()
        calendars = fetched ?? []
        let snapshot = calendars
        broadcast(.refresh(calendars: snapshot))
    }

    public func loadArchived() async {
        let fetched = try? await repository.getArchivedCalendars()
        calendars = fetched ?? []
        let snapshot = calendars
        broadcast(.refresh(calendars: snapshot))
    }

    public func createCalendar(name: String, year: Int, numberOfColumns: Int) async throws {
        let newCalendar = try await repository.createCalendar(name: name, year: year, numberOfColumns: numberOfColumns)
        calendars.append(newCalendar)
        broadcast(.add(item: newCalendar))
    }

    public func updateCalendar(_ calendar: CalendarDataSource) async throws {
        try await repository.saveCalendar(calendar)
        // Refetch the saved calendar from the store so in-memory batches/events
        // get their real DB ids. Without this, newly created batches stay with
        // `id == 0` in memory and navigation that resolves a batch by id becomes
        // ambiguous once more than one unsaved batch exists.
        if let fresh = try? await repository.getCalendar(id: calendar.id) {
            if let idx = calendars.firstIndex(where: { $0.id == calendar.id }) {
                calendars[idx] = fresh
            }
            broadcast(.change(item: fresh))
        } else {
            if let idx = calendars.firstIndex(where: { $0.id == calendar.id }) {
                calendars[idx] = calendar
            }
            broadcast(.change(item: calendar))
        }
    }

    public func archiveCalendar(_ calendar: CalendarDataSource) async throws {
        try await repository.archiveCalendar(calendar.id)
        calendars.removeAll { $0.id == calendar.id }
        broadcast(.delete(item: calendar))
    }

    /// Reactivates a calendar and says so as a **change**, not a delete.
    ///
    /// This was a copy of `archiveCalendar` — evict from the cache, `broadcast(.delete(…))` —
    /// which is the wrong shape for a restore in a way that was invisible until someone
    /// pressed Undo. A delete is a true statement about a permanently deleted calendar and a
    /// false one about a restored one, and the consequence was that the calendar never came
    /// back anywhere: the cache had dropped it, and every list folded in a removal. The
    /// archived list *looked* right, because the card did vanish from it — which is how this
    /// survived: the visible symptom was in the *other* list.
    ///
    /// Refetched like `updateCalendar` does, because the DTO handed in still carries
    /// `isArchived == true`; publishing that would tell the active list to filter the
    /// calendar straight back out.
    public func restoreCalendar(_ calendar: CalendarDataSource) async throws {
        try await repository.restoreCalendar(calendar.id)
        if let fresh = try? await repository.getCalendar(id: calendar.id) {
            if let idx = calendars.firstIndex(where: { $0.id == calendar.id }) {
                calendars[idx] = fresh
            } else {
                calendars.append(fresh)
            }
            broadcast(.change(item: fresh))
        } else {
            // The store would not hand it back. Reactivate the copy we were given rather
            // than publish a calendar that still says it is archived.
            var restored = calendar
            restored.isArchived = false
            calendars.removeAll { $0.id == calendar.id }
            calendars.append(restored)
            broadcast(.change(item: restored))
        }
    }

    public func permanentlyDeleteCalendar(_ calendar: CalendarDataSource) async throws {
        try await repository.deleteCalendar(calendar.id)
        calendars.removeAll { $0.id == calendar.id }
        broadcast(.delete(item: calendar))
    }

    public func getCalendar(id: Int64) async throws -> CalendarDataSource? {
        if let cached = calendars.first(where: { $0.id == id }) {
            return cached
        }
        guard let fetched = try await repository.getCalendar(id: id) else { return nil }
        calendars.append(fetched)
        return fetched
    }

    /// The calendars currently held in memory, with no I/O.
    ///
    /// Distinct from `getAllCalendars()`, which asks the repository. A caller that has
    /// just run `loadActive()` or `loadArchived()` should read the result from here
    /// rather than wait for the `.refresh` broadcast it triggered itself: the change
    /// feed has no replay, and its subscription may not be live yet.
    public func loadedCalendars() -> [CalendarDataSource] {
        calendars
    }

    public func getAllCalendars() async throws -> [CalendarDataSource] {
        try await repository.getAllCalendars()
    }
}
