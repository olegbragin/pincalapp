//
//  CalendarCache.swift
//  PinCalApp
//

import Combine
import Foundation

enum ChangeOperation: Sendable {
    case add(item: CalendarDataSource)
    case delete(item: CalendarDataSource)
    case change(item: CalendarDataSource)
    case refresh(calendars: [CalendarDataSource])
}

actor CalendarCache {
    private var calendars: [CalendarDataSource] = []
    nonisolated(unsafe) let changes = PassthroughSubject<ChangeOperation, Never>()

    private let manager: CalendarManager

    init(manager: CalendarManager) {
        self.manager = manager
    }

    func loadActive() async {
        let fetched = try? await manager.getActiveCalendars()
        calendars = fetched ?? []
        let snapshot = calendars
        await MainActor.run { changes.send(.refresh(calendars: snapshot)) }
    }

    func loadArchived() async {
        let fetched = try? await manager.getArchivedCalendars()
        calendars = fetched ?? []
        let snapshot = calendars
        await MainActor.run { changes.send(.refresh(calendars: snapshot)) }
    }

    func createCalendar(name: String, year: Int, numberOfColumns: Int) async throws -> CalendarDataSource {
        let newCalendar = try await manager.createCalendar(name: name, year: year, numberOfColumns: numberOfColumns)
        calendars.append(newCalendar)
        await MainActor.run { changes.send(.add(item: newCalendar)) }
        return newCalendar
    }

    func updateCalendar(_ calendar: CalendarDataSource) async throws {
        try await manager.updateCalendar(calendar)
        if let idx = calendars.firstIndex(where: { $0.id == calendar.id }) {
            calendars[idx] = calendar
        }
        await MainActor.run { changes.send(.change(item: calendar)) }
    }

    func archiveCalendar(_ calendar: CalendarDataSource) async throws {
        try await manager.archiveCalendar(calendar.id)
        calendars.removeAll { $0.id == calendar.id }
        await MainActor.run { changes.send(.delete(item: calendar)) }
    }

    func restoreCalendar(_ calendar: CalendarDataSource) async throws {
        try await manager.restoreCalendar(calendar.id)
        calendars.removeAll { $0.id == calendar.id }
        await MainActor.run { changes.send(.delete(item: calendar)) }
    }

    func permanentlyDeleteCalendar(_ calendar: CalendarDataSource) async throws {
        try await manager.deleteCalendar(calendar.id)
        calendars.removeAll { $0.id == calendar.id }
        await MainActor.run { changes.send(.delete(item: calendar)) }
    }

    func getCalendar(id: Int64) async throws -> CalendarDataSource? {
        try await manager.getCalendar(id: id)
    }
}
