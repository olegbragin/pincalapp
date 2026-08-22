//
//  CalendarCache.swift
//  PinCalApp
//

import Combine
import Foundation

enum ChangeOperation {
    case add(item: CalendarDataSource)
    case delete(item: CalendarDataSource)
    case change(item: CalendarDataSource)
    case refresh(calendars: [CalendarDataSource])
}

@MainActor
final class CalendarCache {
    static let shared = CalendarCache()

    var calendars: [CalendarDataSource] = []
    let changes = PassthroughSubject<ChangeOperation, Never>()

    private let manager: CalendarManager

    init(manager: CalendarManager = CalendarManager()) {
        self.manager = manager
    }

    func loadActive() {
        Task {
            let fetched = try? await manager.getActiveCalendars()
            calendars = fetched ?? []
            changes.send(.refresh(calendars: calendars))
        }
    }

    func loadArchived() {
        Task {
            let fetched = try? await manager.getArchivedCalendars()
            calendars = fetched ?? []
            changes.send(.refresh(calendars: calendars))
        }
    }

    func createCalendar(name: String, year: Int, numberOfColumns: Int) async throws -> CalendarDataSource {
        let newCalendar = try await manager.createCalendar(name: name, year: year, numberOfColumns: numberOfColumns)
        calendars.append(newCalendar)
        changes.send(.add(item: newCalendar))
        return newCalendar
    }

    func updateCalendar(_ calendar: CalendarDataSource) async throws {
        try await manager.updateCalendar(calendar)
        if let idx = calendars.firstIndex(where: { $0.id == calendar.id }) {
            calendars[idx] = calendar
        }
        changes.send(.change(item: calendar))
    }

    func archiveCalendar(_ calendar: CalendarDataSource) async throws {
        try await manager.archiveCalendar(calendar.id)
        calendars.removeAll { $0.id == calendar.id }
        changes.send(.delete(item: calendar))
    }

    func restoreCalendar(_ calendar: CalendarDataSource) async throws {
        try await manager.restoreCalendar(calendar.id)
        calendars.removeAll { $0.id == calendar.id }
        changes.send(.delete(item: calendar))
    }

    func permanentlyDeleteCalendar(_ calendar: CalendarDataSource) async throws {
        try await manager.deleteCalendar(calendar.id)
        calendars.removeAll { $0.id == calendar.id }
        changes.send(.delete(item: calendar))
    }

    func getCalendar(id: Int64) async throws -> CalendarDataSource? {
        try await manager.getCalendar(id: id)
    }
}
