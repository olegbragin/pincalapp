//
//  ObjectBoxCalendarStorage.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 15.02.2026.
//

import Foundation
import ObjectBox

class ObjectBoxCalendarStorage: CalendarStorage {
    private let store: Store
    private let calendarEntityBox: Box<PPCalendar>
    private let eventEntityBox: Box<PPEvent>
    
    init(store: Store = ObjectBoxFactory.shared.store) {
        self.store = store
        self.calendarEntityBox = store.box(for: PPCalendar.self)
        self.eventEntityBox = store.box(for: PPEvent.self)
    }
    
    func getCalendar(id: Int64) async throws -> CalendarDataSource? {
        try CalendarDataSource(calendarEntityBox.get(id))
    }
    
    @discardableResult
    func saveCalendar(_ calendar: CalendarDataSource) async throws -> Int64 {
        do {
            let calendarid = try calendarEntityBox.put(
                .init(
                    id: UInt64(calendar.id),
                    name: calendar.name,
                    year: calendar.year,
                    numberOfColumns: calendar.numberOfColumns
                )
            )
            guard let ppcalendar = try calendarEntityBox.get(calendarid) else { return -1 }
            let ppevents = calendar.events.map { event in
                PPEvent.init(id: UInt64(event.id), name: event.name, color: event.color, date: event.date)
            }
            try eventEntityBox.remove(ppcalendar.events.map(\.id))
            try eventEntityBox.put(ppevents)
            ppcalendar.events.append(contentsOf: ppevents)
            try ppcalendar.events.applyToDb()
            return Int64(ppcalendar.id)
        } catch {
            print(error)
            return -1
        }
    }
    
    func removeEvents(_ eventIds: [Int64], calendarId: Int64) async throws {
        let calendar = try calendarEntityBox.get(calendarId)
        calendar?.events.removeAll(where: {
            eventIds.contains(Int64($0.id))
        })
        try calendar?.events.applyToDb()
        try eventIds.forEach {
            try eventEntityBox.remove($0)
        }
    }
    
    @discardableResult
    func deleteCalendar(_ calendarId: Int64) async throws -> Int64 {
        guard try calendarEntityBox.contains(UInt64(calendarId)) else { return 0 }
        return Int64(
            try calendarEntityBox.remove(calendarId)
        )
    }
    
    func getAllCalendars() async throws -> [CalendarDataSource] {
        try calendarEntityBox.all().compactMap {
            CalendarDataSource($0)
        }
    }
    
    func close() {
        store.close()
    }
}
