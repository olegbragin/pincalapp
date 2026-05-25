//
//  Calendar.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 15.02.2026.
//

import ObjectBox

class PPCalendar: Entity {
    var id: Id = 0
    var name: String = ""
    var year: Int = 0
    var numberOfColumns: Int = 0
    
    // objectbox: backlink = "calendars"
    var events: ToMany<PPEvent> = nil
    
    init() { }
    
    init(
        id: Id = 0,
        name: String,
        year: Int,
        numberOfColumns: Int
    ) {
        if id > 0 {
            self.id = id
        }
        self.name = name
        self.year = year
        self.numberOfColumns = numberOfColumns
    }
}
