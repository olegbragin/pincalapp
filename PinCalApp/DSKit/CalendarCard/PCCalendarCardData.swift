//
//  CalendarCardData.swift
//  PinCalApp
//

import Foundation

protocol CalendarCardData {
    var id: Int64 { get }
    var name: String { get }
    var numberOfColumns: Int { get }
}
