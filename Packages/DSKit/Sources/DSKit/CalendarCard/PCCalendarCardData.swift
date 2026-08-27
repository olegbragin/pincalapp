//
//  PCCalendarCardData.swift
//  PinCalApp
//

import Foundation

protocol PCCalendarCardData {
    var id: Int64 { get }
    var name: String { get }
    var numberOfColumns: Int { get }
    var isArchived: Bool { get }
}