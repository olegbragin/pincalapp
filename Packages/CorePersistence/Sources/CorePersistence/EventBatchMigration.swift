//
//  EventBatchMigration.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 03.08.2026.
//

import Foundation
import ObjectBox

enum EventBatchMigration {
    private static let hasMigratedKey = "didMigrateEventsToEventBatches"
    
    static func runIfNeeded(store: Store) {
        guard !UserDefaults.standard.bool(forKey: hasMigratedKey) else { return }
        guard let calendars = try? store.box(for: PPCalendar.self).all() else { return }
        
        let batchBox = store.box(for: PPEventBatch.self)
        
        for calendar in calendars where !calendar.events.isEmpty {
            let eventsByColor = Dictionary(grouping: calendar.events, by: \.color)
            for (color, events) in eventsByColor {
                let sortedEvents = events.sorted(by: { $0.date < $1.date })
                guard let firstEvent = sortedEvents.first else { continue }
                let batch = PPEventBatch(title: firstEvent.name, color: color)
                _ = try? batchBox.put(batch)
                batch.events.replace(sortedEvents)
                _ = try? batch.events.applyToDb()
                calendar.eventBatches.append(batch)
            }
            calendar.events.removeAll()
            _ = try? calendar.eventBatches.applyToDb()
            _ = try? store.box(for: PPCalendar.self).put(calendar)
        }
        
        UserDefaults.standard.set(true, forKey: hasMigratedKey)
    }
}
