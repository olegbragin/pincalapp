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
    
    var events: ToMany<PPEvent> = nil
    
    init() { }
    
    init(
        id: Id = 0,
        title: String
    ) {
        if id > 0 {
            self.id = id
        }
        self.id = id
        self.title = title
    }
}
