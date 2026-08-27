//
//  RootSelection.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 19.02.2026.
//

import Foundation
import CorePersistence
import Observation
import SwiftUI

public enum RootSelection: Equatable, Hashable {
    case calendarList
    case archived
}

/// What the detail column of the split view is showing.
public enum DetailSelection: Hashable {
    case calendar(Int64)
}

/// What the batch editor screen should be opened with.
public enum BatchEditorSource: Hashable {
    case newDay(Date)
    case existingBatch(EventBatchDataSource)
}

/// Pages that can be pushed onto the detail column's navigation stack.
public enum AppRoute: Hashable {
    case dayBatches(Date)
    case batchEditor(BatchEditorSource)
}

/// Sheets presented app-wide, driven by the router instead of local view state.
public enum AppSheet: Hashable, Identifiable {
    case addCalendar

    public var id: Self { self }
}
