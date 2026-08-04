//
//  PPEventBatch.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 02.07.2026.
//

import Foundation
import ObjectBox

class PPEventBatch: Entity {
    var id: Id = 0
    var title: String = ""
    var color: String = ""
    var date: Date? = nil
    
    var events: ToMany<PPEvent> = nil
    
    // objectbox: backlink = "eventBatches"
    var calendars: ToMany<PPCalendar> = nil
    
    init() { }
    
    init(
        id: Id = 0,
        title: String,
        color: String = "",
        date: Date? = nil
    ) {
        if id > 0 {
            self.id = id
        }
        self.title = title
        self.color = color
        self.date = date
    }
}
