//
//  EventBatchDataSource.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 02.07.2026.
//

struct EventBatchDataSource: Identifiable, Hashable {
    var id: Int64
    var name: String
    var events: [EventDataSource]
    
    init(
        id: Int64 = 0,
        name: String,
        events: [EventDataSource] = []
    ) {
        self.id = id
        self.name = name
        self.events = events
    }
    
    init?(_ dto: PPEventBatch?) {
        guard let dto else { return nil }
        self.id = Int64(dto.id)
        self.name = dto.title
        self.events = dto.events.compactMap {
            EventDataSource($0)
        }
    }
}

extension EventBatchDataSource: Equatable {
    static func == (lhs: EventBatchDataSource, rhs: EventBatchDataSource) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name
    }
}
