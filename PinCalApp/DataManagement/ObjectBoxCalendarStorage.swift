//
//  ObjectBoxCalendarStorage.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 15.02.2026.
//

import Foundation
import ObjectBox

class ObjectBoxCalendarStorage: CalendarStorage {
    static let shared = ObjectBoxCalendarStorage()
    
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
                    numberOfColumns: calendar.numberOfColumns,
                    isArchived: calendar.isArchived
                )
            )
            guard let ppcalendar = try calendarEntityBox.get(calendarid) else { return -1 }
            
            let batchEntityBox = store.box(for: PPEventBatch.self)
            
            let desiredBatchIDs = Set(calendar.eventBatches.map(\.id))
            let orphanedBatches = ppcalendar.eventBatches.filter { !desiredBatchIDs.contains(Int64($0.id)) }
            for oldBatch in orphanedBatches {
                let eventIDsToRemove = oldBatch.events.map(\.id)
                try batchEntityBox.remove(oldBatch)
                try eventEntityBox.remove(eventIDsToRemove)
            }
            
            for batch in calendar.eventBatches {
                let ppBatch: PPEventBatch
                if batch.id != 0, let existing = try? batchEntityBox.get(UInt64(batch.id)) {
                    ppBatch = existing
                } else {
                    ppBatch = PPEventBatch()
                }
                ppBatch.title = batch.name
                ppBatch.color = batch.colorName
                ppBatch.date = batch.date
                try batchEntityBox.put(ppBatch)
                
                let ppevents = batch.events.map { event in
                    PPEvent(id: UInt64(event.id), name: event.name, color: event.color, date: event.date)
                }
                try eventEntityBox.put(ppevents)
                ppBatch.events.replace(ppevents)
                try ppBatch.events.applyToDb()
                
                if !ppcalendar.eventBatches.contains(where: { $0.id == ppBatch.id }) {
                    ppcalendar.eventBatches.append(ppBatch)
                }
            }
            
            ppcalendar.events.removeAll()
            try ppcalendar.eventBatches.applyToDb()
            try ppcalendar.events.applyToDb()
            return Int64(ppcalendar.id)
        } catch {
            print(error)
            return -1
        }
    }
    
    func removeEvents(_ eventIds: [Int64], calendarId: Int64) async throws {
        guard let calendar = try calendarEntityBox.get(calendarId) else { return }
        for batch in calendar.eventBatches {
            batch.events.removeAll(where: {
                eventIds.contains(Int64($0.id))
            })
            try batch.events.applyToDb()
        }
        calendar.events.removeAll(where: {
            eventIds.contains(Int64($0.id))
        })
        try calendar.events.applyToDb()
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
    
    func getActiveCalendars() async throws -> [CalendarDataSource] {
        do {
            return try calendarEntityBox.query { PPCalendar.isArchived == false }
                .build().find().compactMap { CalendarDataSource($0) }
        } catch {
            print("[ObjectBoxCalendarStorage] getActiveCalendars query failed: \(error). Falling back to getAllCalendars.")
            return try await getAllCalendars().filter { !$0.isArchived }
        }
    }
    
    func getArchivedCalendars() async throws -> [CalendarDataSource] {
        do {
            return try calendarEntityBox.query { PPCalendar.isArchived == true }
                .build().find().compactMap { CalendarDataSource($0) }
        } catch {
            print("[ObjectBoxCalendarStorage] getArchivedCalendars query failed: \(error). Falling back to getAllCalendars.")
            return try await getAllCalendars().filter { $0.isArchived }
        }
    }
    
    func archiveCalendar(_ calendarId: Int64) async throws {
        guard var cal = try calendarEntityBox.get(calendarId) else { return }
        cal.isArchived = true
        try calendarEntityBox.put(cal)
    }
    
    func restoreCalendar(_ calendarId: Int64) async throws {
        guard var cal = try calendarEntityBox.get(calendarId) else { return }
        cal.isArchived = false
        try calendarEntityBox.put(cal)
    }
    
    func close() {
        store.close()
    }

    func subscribeToCalendars(onChange: @escaping () -> Void) -> AnyObject? {
        calendarEntityBox.subscribe(
            dispatchQueue: .main,
            flags: [.sendInitial],
            changeHandler: onChange
        )
    }
}
