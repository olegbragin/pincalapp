//
//  EventBatchDataSource.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 02.07.2026.
//

import Foundation

public struct EventBatchDataSource: Identifiable, Hashable {
    public var id: Int64
    public var name: String
    public var colorName: String
    public var events: [EventDataSource]
    public var date: Date?
    public let timestamp: UUID?
    
    public init(
        id: Int64 = 0,
        name: String,
        colorName: String = "",
        events: [EventDataSource] = [],
        date: Date? = nil,
        timestamp: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.colorName = colorName
        self.events = events
        self.date = date
        self.timestamp = timestamp
    }
    
    init?(_ dto: PPEventBatch?) {
        guard let dto else { return nil }
        self.id = Int64(dto.id)
        self.name = dto.title
        self.colorName = dto.color
        self.date = dto.date
        self.events = dto.events.compactMap {
            EventDataSource($0)
        }
        self.timestamp = nil
    }
}

extension EventBatchDataSource: Equatable {
    public static func == (lhs: EventBatchDataSource, rhs: EventBatchDataSource) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.colorName == rhs.colorName &&
        lhs.events == rhs.events &&
        lhs.date == rhs.date &&
        lhs.timestamp == rhs.timestamp
    }
}
