//
//  PinCalendar.swift
//  CoreDomain
//
//  Created by Oleg Bragin on 28.09.2026.
//

import Foundation

/// A calendar's management data: what it is called, which year it shows, how its grid
/// is laid out, and whether it is archived.
///
/// The abstraction layer **above** `CalendarDataSource`, which stays in
/// `CorePersistence` where the full object graph lives. `CalendarDataSource` carries
/// `events` and `eventBatches` because `PPCalendar` holds both relations and the
/// storage layer needs the whole thing. Nothing above the data edge needs it to.
///
/// That user is `CalendarListFeature`, which is the calendar-management screen: it
/// lists calendars, renames one, archives one, restores one, deletes one. It reads
/// only the five properties below, so those are all this carries. Event and batch
/// management belongs to the batch-assembly pipeline, which reads
/// `eventBatches(calendarID:)` through `CalendarPersisting` instead.
///
/// Not named `Calendar`: a type called `Calendar` in a module that also imports
/// `Foundation` shadows `Foundation.Calendar` in every file that sees both, and
/// `PCCalendarDataProvider` holds one.
public struct PinCalendar: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var name: String
    public var year: Int
    public var numberOfColumns: Int
    public var isArchived: Bool

    public init(
        id: Int64 = 0,
        name: String,
        year: Int,
        numberOfColumns: Int,
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.year = year
        self.numberOfColumns = numberOfColumns
        self.isArchived = isArchived
    }
}
