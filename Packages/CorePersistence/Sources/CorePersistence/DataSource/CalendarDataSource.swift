//
//  CalendarDataSource.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 15.02.2026.
//

public struct CalendarDataSource: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var name: String
    public var year: Int
    public var numberOfColumns: Int
    public var isArchived: Bool
    public var events: [EventDataSource]
    public var eventBatches: [EventBatchDataSource]
    
    public init(
        id: Int64 = 0,
        name: String,
        year: Int,
        numberOfColumns: Int,
        isArchived: Bool = false,
        events: [EventDataSource] = [],
        eventBatches: [EventBatchDataSource] = []
    ) {
        self.id = id
        self.name = name
        self.year = year
        self.numberOfColumns = numberOfColumns
        self.isArchived = isArchived
        self.events = events
        self.eventBatches = eventBatches
    }
    
    init?(_ dto: PPCalendar?) {
        guard let dto else { return nil }
        self.id = Int64(dto.id)
        self.name = dto.name
        self.year = dto.year
        self.numberOfColumns = dto.numberOfColumns
        self.isArchived = dto.isArchived
        self.eventBatches = dto.eventBatches.compactMap {
            EventBatchDataSource($0)
        }
        self.events = eventBatches.flatMap(\.events).isEmpty
            ? dto.events.compactMap { EventDataSource($0) }
            : eventBatches.flatMap(\.events)
    }
}

extension CalendarDataSource: Equatable {
    public static func == (lhs: CalendarDataSource, rhs: CalendarDataSource) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.year == rhs.year && lhs.numberOfColumns == rhs.numberOfColumns && lhs.isArchived == rhs.isArchived
    }
}
