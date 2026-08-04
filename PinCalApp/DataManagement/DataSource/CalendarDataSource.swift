//
//  CalendarDataSource.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 15.02.2026.
//

struct CalendarDataSource: Identifiable, Hashable {
    var id: Int64
    var name: String
    var year: Int
    var numberOfColumns: Int
    var events: [EventDataSource]
    var eventBatches: [EventBatchDataSource]
    
    init(
        id: Int64 = 0,
        name: String,
        year: Int,
        numberOfColumns: Int,
        events: [EventDataSource] = [],
        eventBatches: [EventBatchDataSource] = []
    ) {
        self.id = id
        self.name = name
        self.year = year
        self.numberOfColumns = numberOfColumns
        self.events = events
        self.eventBatches = eventBatches
    }
    
    init?(_ dto: PPCalendar?) {
        guard let dto else { return nil }
        self.id = Int64(dto.id)
        self.name = dto.name
        self.year = dto.year
        self.numberOfColumns = dto.numberOfColumns
        self.eventBatches = dto.eventBatches.compactMap {
            EventBatchDataSource($0)
        }
        self.events = eventBatches.flatMap(\.events).isEmpty
            ? dto.events.compactMap { EventDataSource($0) }
            : eventBatches.flatMap(\.events)
    }
}

extension CalendarDataSource: Equatable {
    static func == (lhs: CalendarDataSource, rhs: CalendarDataSource) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.year == rhs.year && lhs.numberOfColumns == rhs.numberOfColumns
    }
}
