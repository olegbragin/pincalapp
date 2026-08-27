//
//  CalendarRepository.swift
//  PinCalApp
//
//  Single persistence contract — replaces CalendarStorage + CalendarManager indirection.
//  Conforms to Sendable for Swift 6 actor isolation.
//

import Foundation

public protocol CalendarRepository: Sendable {
    func getCalendar(id: Int64) async throws -> CalendarDataSource?
    @discardableResult func saveCalendar(_ calendar: CalendarDataSource) async throws -> Int64
    @discardableResult func deleteCalendar(_ calendarId: Int64) async throws -> Int64
    func getAllCalendars() async throws -> [CalendarDataSource]
    func getActiveCalendars() async throws -> [CalendarDataSource]
    func getArchivedCalendars() async throws -> [CalendarDataSource]
    func archiveCalendar(_ calendarId: Int64) async throws
    func restoreCalendar(_ calendarId: Int64) async throws
    func removeEvents(_ eventIds: [Int64], calendarId: Int64) async throws

    // Convenience — default impl in extension
    func createCalendar(name: String, year: Int, numberOfColumns: Int) async throws -> CalendarDataSource
}

extension CalendarRepository {
    public func createCalendar(name: String, year: Int, numberOfColumns: Int) async throws -> CalendarDataSource {
        var c = CalendarDataSource(name: name, year: year, numberOfColumns: numberOfColumns)
        let id = try await saveCalendar(c)
        c.id = id
        return c
    }
}
