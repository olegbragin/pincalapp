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
    
    var addEditEventBatchModel = AddEditEventBatchViewModel()
    var eventBatchesToDelete = [EventBatchDataSource]()
    var eventBatchesSelectedToDelete = [EventBatchDataSource]()
    var isEditing = false

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
    
    func prepareAddEditBatchViewModel(with eventBatch: EventBatchDataSource?) {
        addEditEventBatchModel.eventBatchId = eventBatch?.id ?? 0
        addEditEventBatchModel.eventBatchName = eventBatch?.name ?? ""
        addEditEventBatchModel.selectedColor = PCColorOption(eventBatch?.colorName ?? "") ?? .option1
        addEditEventBatchModel.date = eventBatch?.date ?? (eventBatch == nil ? selectedDay : nil)
        addEditEventBatchModel.selectedDays = selectedDay.map { [$0] } ?? []
        addEditEventBatchModel.timestamp = eventBatch?.timestamp ?? UUID()
        addEditEventBatchModel.prepare(with: eventBatch?.events ?? [])
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
        addEditEventBatchModel.reset()
    }
    
    func reset() {
        eventBatches = []
        eventBatchesSelectedToDelete = []
        isEditing = false
        addEditEventBatchModel.reset()
    }
}

extension EventBatchDataSource {
    var color: Color {
        let colorNameToUse = colorName.isEmpty ? events.first?.color : colorName
        guard let colorNameToUse, !colorNameToUse.isEmpty else { return .clear }
        return Color(colorNameToUse)
    }

    func eventsForDay(_ day: Date?) -> [EventDataSource] {
        guard let day else { return events.sorted { $0.date < $1.date } }
        return events
            .filter { Calendar.autoupdatingCurrent.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date < $1.date }
    }
}
