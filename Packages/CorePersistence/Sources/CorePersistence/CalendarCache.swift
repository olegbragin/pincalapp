//
//  CalendarCache.swift
//  PinCalApp
//

import Combine
import Foundation

public enum ChangeOperation: Sendable {
    case add(item: CalendarDataSource)
    case delete(item: CalendarDataSource)
    case change(item: CalendarDataSource)
    case refresh(calendars: [CalendarDataSource])
}

public actor CalendarCache {
    private var calendars: [CalendarDataSource] = []
    public nonisolated(unsafe) let changes = PassthroughSubject<ChangeOperation, Never>()

    private let repository: any CalendarRepository

    public init(repository: any CalendarRepository) {
        self.repository = repository
    }

    public func loadActive() async {
        let fetched = try? await repository.getActiveCalendars()
        calendars = fetched ?? []
        let snapshot = calendars
        await MainActor.run { changes.send(.refresh(calendars: snapshot)) }
    }

    public func loadArchived() async {
        let fetched = try? await repository.getArchivedCalendars()
        calendars = fetched ?? []
        let snapshot = calendars
        await MainActor.run { changes.send(.refresh(calendars: snapshot)) }
    }

    public func createCalendar(name: String, year: Int, numberOfColumns: Int) async throws {
        let newCalendar = try await repository.createCalendar(name: name, year: year, numberOfColumns: numberOfColumns)
        calendars.append(newCalendar)
        await MainActor.run { changes.send(.add(item: newCalendar)) }
    }

    public func updateCalendar(_ calendar: CalendarDataSource) async throws {
        try await repository.saveCalendar(calendar)
        if let idx = calendars.firstIndex(where: { $0.id == calendar.id }) {
            calendars[idx] = calendar
        }
        await MainActor.run { changes.send(.change(item: calendar)) }
    }

    public func archiveCalendar(_ calendar: CalendarDataSource) async throws {
        try await repository.archiveCalendar(calendar.id)
        calendars.removeAll { $0.id == calendar.id }
        await MainActor.run { changes.send(.delete(item: calendar)) }
    }

    public func restoreCalendar(_ calendar: CalendarDataSource) async throws {
        try await repository.restoreCalendar(calendar.id)
        calendars.removeAll { $0.id == calendar.id }
        await MainActor.run { changes.send(.delete(item: calendar)) }
    }

    public func permanentlyDeleteCalendar(_ calendar: CalendarDataSource) async throws {
        try await repository.deleteCalendar(calendar.id)
        calendars.removeAll { $0.id == calendar.id }
        await MainActor.run { changes.send(.delete(item: calendar)) }
    }

    public func getCalendar(id: Int64) async throws -> CalendarDataSource? {
        if let cached = calendars.first(where: { $0.id == id }) {
            return cached
        }
        guard let fetched = try await repository.getCalendar(id: id) else { return nil }
        calendars.append(fetched)
        return fetched
    }

    public func getAllCalendars() async throws -> [CalendarDataSource] {
        try await repository.getAllCalendars()
    }
}
