//
//  Event.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 15.02.2026.
//

import Foundation
import ObjectBox

class PPEvent: Entity {
    var id: Id = 0
    var name: String = ""
    var color: String = ""
    var date: Date = Date()
    
    var calendars: ToMany<PPCalendar> = nil
    
    init() { }
    
    init(
        id: Id = 0,
        name: String,
        color: String,
        date: Date
    ) {
        if id > 0 {
            self.id = id
        }
        self.id = id
        self.name = name
        self.color = color
        self.date = date
    }
}
