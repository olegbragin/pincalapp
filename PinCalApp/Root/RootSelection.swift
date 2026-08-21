//
//  Navigatino.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 19.02.2026.
//

import Foundation

enum RootSelection: Equatable, Hashable {
    case calendarList
    case archived
}

enum AppRoute: Hashable {
    case calendarDetail(Int64)
    case batchList
    case batchEditor
}
