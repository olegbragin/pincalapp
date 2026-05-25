//
//  CalendarManager.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 15.02.2026.
//

struct CalendarManager {
    private let service: CalendarStorage
    
    init(service: CalendarStorage = ObjectBoxCalendarStorage()) {
        self.service = service
    }
    
    // Делегируем методы сервису
    func createCalendar(name: String, year: Int, numberOfColumns: Int) async throws -> CalendarDataSource {
        var calendarToCreate = CalendarDataSource(name: name, year: year, numberOfColumns: numberOfColumns)
        let id = try await service.saveCalendar(calendarToCreate)
        calendarToCreate.id = id
        return calendarToCreate
    }
    
    func getCalendar(id: Int64) async throws -> CalendarDataSource? {
        try await service.getCalendar(id: id)
    }
    
    func updateCalendar(_ calendar: CalendarDataSource) async throws {
        try await service.saveCalendar(calendar)
    }
    
    func deleteCalendar(_ calendarId: Int64) async throws {
        try await service.deleteCalendar(calendarId)
    }
    
    func getAllCalendars() async throws -> [CalendarDataSource] {
        try await service.getAllCalendars()
    }
    
    func removeEvents(_ eventIds: [Int64], calendarId: Int64) async throws {
        try await service.removeEvents(eventIds, calendarId: calendarId)
    }
}

