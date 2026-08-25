//
//  RootSelection.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 19.02.2026.
//

import Foundation

enum RootSelection: Equatable, Hashable {
    case calendarList
    case archived
}

/// What the detail column of the split view is showing.
enum DetailSelection: Hashable {
    case calendar(Int64)
}

/// What the batch editor screen should be opened with.
enum BatchEditorSource: Hashable {
    case newDay(Date)
    case existingBatch(EventBatchDataSource)
}

/// Pages that can be pushed onto the detail column's navigation stack.
enum AppRoute: Hashable {
    case dayBatches(Date)
    case batchEditor(BatchEditorSource)
}

/// Sheets presented app-wide, driven by the router instead of local view state.
enum AppSheet: Hashable, Identifiable {
    case addCalendar

    var id: Self { self }
}
