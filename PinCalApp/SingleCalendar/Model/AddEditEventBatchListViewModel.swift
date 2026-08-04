//
//  AddEditEventBatchListViewModel.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 08.07.2026.
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AddEditEventBatchListViewModel {
    private(set) var eventBatches = [EventBatchDataSource]()
    private(set) var selectedDay: Date?
    
    var addEditEventBatchModel = AddEditEventBatchViewModel()
    var eventBatchesToChange = [EventBatchDataSource]()
    var eventBatchesToDelete = [EventBatchDataSource]()
    var eventBatchesSelectedToDelete = [EventBatchDataSource]()
    var isEditing = false

    func removeBatches(at indexPaths: IndexSet) {
        indexPaths.forEach {
            let eventBatchRemoved = eventBatches.remove(at: $0)
            eventBatchesSelectedToDelete.append(eventBatchRemoved)
        }
    }
    
    func apply(with eventBatch: EventBatchDataSource) {
        if let batchToReplace = eventBatches.first(where: { $0.id == eventBatch.id || $0.timestamp == eventBatch.timestamp }),
           let indexToReplace = eventBatches.firstIndex(of: batchToReplace) {
            eventBatches[indexToReplace] = eventBatch
        } else {
            eventBatches.append(eventBatch)
        }
        eventBatchesToChange = eventBatches
    }
    
    func prepare(with eventBatches: [EventBatchDataSource], and selectedDay: Date?) {
        self.selectedDay = selectedDay
        self.eventBatches = eventBatches.sorted {
            ($0.events.map(\.date).min() ?? .distantPast) < ($1.events.map(\.date).min() ?? .distantPast)
        }
    }
    
    func prepareAddEditBatchViewModel(with eventBatch: EventBatchDataSource?) {
        addEditEventBatchModel.eventBatchId = eventBatch?.id ?? 0
        addEditEventBatchModel.eventBatchName = eventBatch?.name ?? "1"
        addEditEventBatchModel.selectedColor = ColorOption(eventBatch?.colorName ?? "") ?? .option1
        addEditEventBatchModel.date = eventBatch?.date ?? (eventBatch == nil ? selectedDay : nil)
        addEditEventBatchModel.timestamp = eventBatch?.timestamp ?? UUID()
        addEditEventBatchModel.prepare(with: eventBatch?.events ?? [])
        addEditEventBatchModel.isPresented = true
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
}
