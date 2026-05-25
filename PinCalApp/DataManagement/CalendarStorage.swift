//
//  CalendarStorage.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 15.02.2026.
//

protocol CalendarStorage {
    func getCalendar(id: Int64) async throws -> CalendarDataSource?
    
    @discardableResult
    func saveCalendar(_ calendar: CalendarDataSource) async throws -> Int64
    
    @discardableResult
    func deleteCalendar(_ calendarId: Int64) async throws -> Int64
    
    func getAllCalendars() async throws -> [CalendarDataSource]
    
    func removeEvents(_ eventId: [Int64], calendarId: Int64) async throws
}
