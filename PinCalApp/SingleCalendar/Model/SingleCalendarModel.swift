//
//  Untitled.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 04.02.2026.
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class SingleCalendarModel {
    enum Action {
        case change
        case delete
    }
    
    enum State {
        case empty
        case content
        case loading
    }
    
    private let dataProvider = USCalendarDataProvider()
    private let manager: CalendarManager
    
    private var originalBatches: [EventBatchDataSource] = []
    private var addedEvents: Set<EventDataSource> = []
    
    private(set) var calendarid: Int64
    private(set) var label: String = ""
    
    let daySelectionManager = USCalendarDaySelectionManager()
    
    var selectedColor: ColorOption?
    
    private(set) var yearModel = USCalendarYearModel()
    private(set) var addEditBatchListViewModel = AddEditEventBatchListViewModel()
    
    var state: State = .empty
    var isEditPresented = false
    var isEditScreenPresented = false
    var isLegendSheetPresented = false
    private(set) var isRoutingToBatchEditor = false
    
    private var originalEvents: Set<EventDataSource> {
        Set(originalBatches.flatMap(\.events))
    }
    
    var selectedEvents: [EventDataSource] {
        guard !daySelectionManager.selectedDays.isEmpty else { return [] }
        return originalEvents.filter { event in
            daySelectionManager.selectedDays.contains { date in
                isSameDay(event.date, date)
            }
        }
    }
    
    func hasEvents(on date: Date) -> Bool {
        originalBatches.contains { batch in
            batch.events.contains { event in
                isSameDay(event.date, date)
            } || (batch.date.map { isSameDay($0, date) } ?? false)
        }
    }
    
    init(calendarid: Int64, manager: CalendarManager = CalendarManager()) {
        self.calendarid = calendarid
        self.manager = manager
    }
    
    var isColorPickerDisabled: Bool {
        daySelectionManager.selectionMode == .multiple && selectedColor != nil && !addedEvents.isEmpty
    }
    
    func changeEvent(_ event: EventDataSource) {
        if addedEvents.contains(event) {
            addedEvents.remove(at: addedEvents.firstIndex(of: event)!)
        } else {
            addedEvents.insert(event)
        }
        updateYearModel(with: originalEvents.union(addedEvents))
        daySelectionManager.selectedDays = []
    }
    
    func fetch() async {
        // reset()
        
        guard state != .content, !Task.isCancelled else { return }
        // isLoading = true
        
        guard let calendar = try? await self.manager.getCalendar(id: calendarid) else {
            state = .empty
            return
        }
        
        // try? await Task.sleep(for: .seconds(3))
        
        label = calendar.name
        yearModel.months = dataProvider.months(forYear: calendar.year).map {
            USCalendarMonthModel(dto: $0, daySelectionManager: daySelectionManager)
        }
        yearModel.numberOfCurrentMonth = dataProvider.numberOfCurrentMonth
        yearModel.set(initialNumberOfColumns: calendar.numberOfColumns)
        
        originalBatches = calendar.eventBatches
        updateYearModel(with: originalEvents)
        state = .content
    }
    
    func save(for calendarId: Int64) {
        Task { [weak self] in
            guard let self else { return }
            guard var persistedCalendar = try? await self.manager.getCalendar(id: calendarId) else { return }
            persistedCalendar.numberOfColumns = yearModel.internalNumberOfColumns
            persistedCalendar.eventBatches = originalBatches
            try? await manager.updateCalendar(persistedCalendar)
            if let refreshedCalendar = try? await self.manager.getCalendar(id: calendarId) {
                originalBatches = refreshedCalendar.eventBatches
                updateYearModel(with: originalEvents)
            }
            state = .content
        }
    }
    
    func prepareAddEditEventBatchViewModel() {
        guard !addedEvents.isEmpty else { return }
        let sortedEvents = addedEvents.sorted { $0.date < $1.date }
        let addEditModel = addEditBatchListViewModel.addEditEventBatchModel
        addEditModel.eventBatchId = 0
        addEditModel.eventBatchName = sortedEvents.first?.name ?? ""
        addEditModel.selectedColor = ColorOption(sortedEvents.first?.color ?? "") ?? selectedColor
        addEditModel.date = nil
        addEditModel.selectedDays = sortedEvents.map(\.date)
        addEditModel.timestamp = UUID()
        addEditModel.prepare(with: sortedEvents)
        isEditScreenPresented = true
    }
    
    func prepareAddEditEventBatchViewModel(for date: Date) {
        let addEditModel = addEditBatchListViewModel.addEditEventBatchModel
        addEditModel.eventBatchId = 0
        addEditModel.eventBatchName = ""
        addEditModel.selectedColor = nil
        addEditModel.date = date
        addEditModel.selectedDays = [date]
        addEditModel.timestamp = UUID()
        addEditModel.prepare(with: [])
        isEditScreenPresented = true
    }
    
    func routeToBatchEditor() {
        isEditPresented = false
        isRoutingToBatchEditor = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            isRoutingToBatchEditor = false
            isEditScreenPresented = true
        }
    }
    
    func handleSelectionConfirmation() {
        guard !addedEvents.isEmpty else {
            cancelMultipleChanges()
            return
        }
        prepareAddEditEventBatchViewModel()
    }
    
    func commitNewBatch() {
        guard let eventBatch = addEditBatchListViewModel.addEditEventBatchModel.eventBatch,
              eventBatch.id == 0 else { return }
        originalBatches.append(eventBatch)
        updateYearModel(with: originalEvents)
        save(for: calendarid)
    }
    
    func cancelMultipleChanges() {
        updateYearModel(with: originalEvents)
        daySelectionManager.toggleSelectionMode()
        addedEvents = []
        selectedColor = nil
    }
    
    func prepareAddEditBatchListViewModel(with selectedDays: Set<Date>) {
        guard let selectedDay = selectedDays.first else {
            isEditPresented = false
            addEditBatchListViewModel.reset()
            return
        }
        let dayBatches = originalBatches.filter { batch in
            batch.events.contains { event in
                isSameDay(event.date, selectedDay)
            } || (batch.date.map { isSameDay($0, selectedDay) } ?? false)
        }
        addEditBatchListViewModel.prepare(with: dayBatches, and: selectedDay)
        isEditPresented = true
    }
    
    func onBatchListDismissed() {
        daySelectionManager.selectedDays = []
        if !isRoutingToBatchEditor {
            addEditBatchListViewModel.reset()
        }
    }
    
    func apply(batches: [EventBatchDataSource], action: Action, for calendarId: Int64) {
        switch action {
        case .change:
            var mergedBatches = originalBatches
            for batch in batches {
                if let index = mergedBatches.firstIndex(where: { key(for: $0) == key(for: batch) }) {
                    mergedBatches[index] = batch
                } else {
                    mergedBatches.append(batch)
                }
            }
            originalBatches = mergedBatches
            updateYearModel(with: originalEvents)
        case .delete:
            for batch in batches {
                originalBatches.removeAll(where: { key(for: $0) == key(for: batch) })
            }
            updateYearModel(with: originalEvents)
        }
        save(for: calendarId)
        prepareAddEditBatchListViewModel(with: daySelectionManager.selectedDays)
    }
    
    func reset() {
        label = ""
        state = .empty
        isEditPresented = false
        isEditScreenPresented = false
        isRoutingToBatchEditor = false
        isLegendSheetPresented = false
        addEditBatchListViewModel.reset()
    }
    
    func resetSelectedDays() {
        daySelectionManager.selectedDays = []
        isRoutingToBatchEditor = false
        if daySelectionManager.selectionMode == .multiple {
            commitNewBatch()
            daySelectionManager.toggleSelectionMode()
            addedEvents = []
            selectedColor = nil
            updateYearModel(with: originalEvents)
        } else {
            commitNewBatch()
        }
        addEditBatchListViewModel.addEditEventBatchModel.reset()
    }
    
    private enum BatchMergeKey: Hashable {
        case persisted(Int64)
        case pending(UUID)
        case unsaved(Int)
    }
    
    private func key(for batch: EventBatchDataSource) -> BatchMergeKey {
        if batch.id != 0 {
            return .persisted(batch.id)
        }
        if let timestamp = batch.timestamp {
            return .pending(timestamp)
        }
        return .unsaved(batch.hashValue)
    }
    
    private func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        let lhsComponents = dataProvider.dateComponents(forDate: lhs)
        let rhsComponents = dataProvider.dateComponents(forDate: rhs)
        return
            lhsComponents.day == rhsComponents.day &&
            lhsComponents.month == rhsComponents.month &&
            lhsComponents.year == rhsComponents.year
    }
    
    private func updateYearModel(with events: Set<EventDataSource>) {
        yearModel.months.forEach { month in
            month.weeks.forEach { week in
                week.days
                    .filter { day in
                        day.isInCurrentMonth
                    }
                    .forEach { day in
                        guard let dayDate = day.date else { return }
                        let dayEvents = events.filter {
                            isSameDay($0.date, dayDate)
                        }
                        let dayBatchColors = originalBatches.compactMap { batch -> String? in
                            guard let batchDate = batch.date, isSameDay(batchDate, dayDate) else { return nil }
                            return batch.colorName
                        }
                        day.events = dayEvents.map(\.color) + dayBatchColors.filter { !$0.isEmpty }
                    }
            }
        }
    }
}
