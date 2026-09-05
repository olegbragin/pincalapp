//
//  AddEditEventBatchListViewModel.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 08.07.2026.
//

import Foundation
import Observation
import SwiftUI
import CorePersistence
import DSKit

@MainActor
@Observable
public final class AddEditEventBatchListViewModel {
    private(set) var eventBatches = [EventBatchDataSource]()
    private(set) var selectedDay: Date?

    // Shared connection to the batch editor. Both the batch list and the batch
    // editor view models observe/mutate these managers, so they stay in sync
    // without either owning the other.
    let eventsSelectionManager: PCEventsSelectionManager
    let daySelectionManager: PCCalendarDaySelectionManager
    var eventBatchesToDelete = [EventBatchDataSource]()
    var eventBatchesSelectedToDelete = [EventBatchDataSource]()
    var isEditing = false

    init(
        eventsSelectionManager: PCEventsSelectionManager = PCEventsSelectionManager(),
        daySelectionManager: PCCalendarDaySelectionManager = PCCalendarDaySelectionManager()
    ) {
        self.eventsSelectionManager = eventsSelectionManager
        self.daySelectionManager = daySelectionManager
    }

    func removeBatches(at indexPaths: IndexSet) {
        let removedBatches = indexPaths.map { eventBatches[$0] }
        indexPaths.sorted(by: >).forEach { eventBatches.remove(at: $0) }
        eventBatchesToDelete = removedBatches
    }
    
    func prepare(with eventBatches: [EventBatchDataSource], and selectedDay: Date?) {
        self.selectedDay = selectedDay
        self.eventBatches = eventBatches.sorted {
            ($0.events.map(\.date).min() ?? .distantPast) < ($1.events.map(\.date).min() ?? .distantPast)
        }
        isEditing = true
    }
    
    func commitDelete() {
        eventBatchesToDelete = eventBatchesSelectedToDelete
        eventBatchesSelectedToDelete = []
        isEditing = false
    }
    
    func cancel() {
        eventBatches.append(contentsOf: eventBatchesSelectedToDelete)
        eventBatchesSelectedToDelete = []
        isEditing = false
    }
    
    func reset() {
        eventBatches = []
        eventBatchesSelectedToDelete = []
        isEditing = false
    }
}

extension EventBatchDataSource {
    var color: Color {
        let colorNameToUse = colorName.isEmpty ? events.first?.color : colorName
        guard let colorNameToUse, !colorNameToUse.isEmpty else { return .clear }
        return Color.dsKit.eventColor(named: colorNameToUse)
    }

    func eventsForDay(_ day: Date?) -> [EventDataSource] {
        guard let day else { return events.sorted { $0.date < $1.date } }
        return events
            .filter { Calendar.autoupdatingCurrent.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date < $1.date }
    }
}
