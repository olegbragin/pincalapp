//
//  RootNavigation.swift
//  PinCalApp
//

import Observation

@Observable
class RootNavigation {
    var selectedCategory: RootSelection? = .calendarList
    var selectedCalendarId: Int64?
}
