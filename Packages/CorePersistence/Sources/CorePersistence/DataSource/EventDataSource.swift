//
//  Untitled.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 15.02.2026.
//

import Foundation

public struct EventDataSource: Identifiable, Hashable {
    public var id: Int64
    public var name: String
    public var color: String
    public var date: Date
    public let timestamp: UUID?
    
    public init(id: Int64 = 0, name: String, date: Date, color: String, timestamp: UUID? = nil) {
        self.id = id
        self.name = name
        self.date = date
        self.color = color
        self.timestamp = timestamp
    }
    
    init?(_ dto: PPEvent?) {
        guard let dto else { return nil }
        self.id =  Int64(dto.id)
        self.name = dto.name
        self.date = dto.date
        self.color = dto.color
        self.timestamp = nil
    }
    
    public func withColor(_ color: String) -> EventDataSource {
        EventDataSource(id: id, name: name, date: date, color: color, timestamp: timestamp)
    }
    
    public func withTimestamp(_ timestamp: UUID?) -> EventDataSource {
        EventDataSource(id: id, name: name, date: date, color: color, timestamp: timestamp)
    }
}

extension EventDataSource: Equatable {
    public static func == (lhs: EventDataSource, rhs: EventDataSource) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.date == rhs.date &&
        lhs.color == rhs.color &&
        lhs.timestamp == rhs.timestamp
    }
}
