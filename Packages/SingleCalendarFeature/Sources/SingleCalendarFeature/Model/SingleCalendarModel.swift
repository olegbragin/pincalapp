//
//  Untitled.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 04.02.2026.
//

import Foundation
import Observation
import SwiftUI
import CorePersistence
import AppNavigation
import DSKit
import CoreDomain
import Combine

@MainActor
@Observable
public final class SingleCalendarModel {
    public enum State {
        case empty
        case content
        case loading
    }
    
    private let dataProvider = PCCalendarDataProvider()
    private let cache: CalendarCache
    
    private var originalBatches: [EventBatchDataSource] = []
    private var addedEvents: Set<EventDataSource> = []
    
    public private(set) var calendarid: Int64
    public private(set) var label: String = ""
    public private(set) var isArchived: Bool = false
    
    public let daySelectionManager = PCCalendarDaySelectionManager()
    
    public var selectedColor: PCColorOption?
    
    public private(set) var yearModel = PCCalendarYearModel()
    public private(set) var addEditBatchListViewModel = AddEditEventBatchListViewModel()
    
    public var state: State = .empty
    
    @ObservationIgnored private var cancellable: AnyCancellable?
    
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
    
    public func hasEvents(on date: Date) -> Bool {
        originalBatches.contains { batch in
            batch.events.contains { event in
                isSameDay(event.date, date)
            } || (batch.date.map { isSameDay($0, date) } ?? false)
        }
    }

    /// Decides where navigation should go for a day-selection change and
    /// prepares the corresponding editor state. Returns `nil` when no
    /// navigation is needed.
    public func route(for selectedDays: Set<Date>) -> AppRoute? {
        guard !isArchived, let day = selectedDays.first else { return nil }

        if daySelectionManager.selectionMode == .multiple {
            if let selectedColor {
                changeEvent(EventDataSource(name: "", date: day, color: selectedColor.colorName))
            }
            return nil
        }

        if hasEvents(on: day) {
            prepareAddEditBatchListViewModel(with: selectedDays)
            return .dayBatches(day)
        } else {
            prepareAddEditEventBatchViewModel(for: day)
            return .batchEditor(.newDay(day))
        }
    }
    
    public init(calendarid: Int64, cache: CalendarCache) {
        self.calendarid = calendarid
        self.cache = cache
        cancellable = cache.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] operation in
                guard let self else { return }
                if case .change(let item) = operation, item.id == calendarid {
                    Task { @MainActor [weak self] in
                        await self?.fetch(force: true)
                    }
                }
            }
    }
    
    public var isColorPickerDisabled: Bool {
        daySelectionManager.selectionMode == .multiple && selectedColor != nil && !addedEvents.isEmpty
    }
    
    public func changeEvent(_ event: EventDataSource) {
        if addedEvents.contains(event) {
            addedEvents.remove(at: addedEvents.firstIndex(of: event)!)
        } else {
            addedEvents.insert(event)
        }
        updateDayModel(at: event.date, with: originalEvents.union(addedEvents))
        daySelectionManager.selectedDays = []
    }
    
    public func fetch(force: Bool = false) async {
        guard force || state != .content, !Task.isCancelled else { return }
        
        guard let calendar = try? await self.cache.getCalendar(id: calendarid) else {
            state = .empty
            return
        }
        
        label = calendar.name
        isArchived = calendar.isArchived
        // Build the year model only once. Rebuilding it on every fetch would
        // swap out the PCCalendarDayModel instances the views are bound to,
        // so event updates would not be observed and committed days would
        // silently stop rendering. Event changes are applied in-place below.
        if yearModel.months.isEmpty {
            yearModel.months = dataProvider.months(forYear: calendar.year).map {
                PCCalendarMonthModel(dto: $0, daySelectionManager: daySelectionManager)
            }
            yearModel.numberOfCurrentMonth = dataProvider.numberOfCurrentMonth
            yearModel.set(initialNumberOfColumns: calendar.numberOfColumns)
        }
        
        originalBatches = calendar.eventBatches
        updateYearModel(with: originalEvents)
        state = .content
    }
    
    public func save(for calendarId: Int64) {
        let batches = originalBatches
        let columns = yearModel.internalNumberOfColumns
        Task { [cache] in
            guard var persistedCalendar = try? await cache.getCalendar(id: calendarId) else { return }
            persistedCalendar.numberOfColumns = columns
            persistedCalendar.eventBatches = batches
            try? await cache.updateCalendar(persistedCalendar)
        }
    }
    
    public func prepareAddEditEventBatchViewModel() {
        guard !addedEvents.isEmpty else { return }
        let sortedEvents = addedEvents.sorted { $0.date < $1.date }
        let addEditModel = addEditBatchListViewModel.addEditEventBatchModel
        addEditModel.eventBatchId = 0
        addEditModel.eventBatchName = sortedEvents.first?.name ?? ""
        addEditModel.selectedColor = PCColorOption(sortedEvents.first?.color ?? "") ?? selectedColor
        addEditModel.date = nil
        addEditModel.selectedDays = sortedEvents.map(\.date)
        addEditModel.timestamp = UUID()
        addEditModel.prepare(with: sortedEvents)
    }
    
    public func prepareAddEditEventBatchViewModel(for date: Date) {
        let addEditModel = addEditBatchListViewModel.addEditEventBatchModel
        addEditModel.eventBatchId = 0
        addEditModel.eventBatchName = ""
        addEditModel.selectedColor = .option1
        addEditModel.date = date
        addEditModel.selectedDays = [date]
        addEditModel.timestamp = UUID()
        addEditModel.prepare(with: [
            EventDataSource(name: "", date: date, color: PCColorOption.option1.colorName)
        ])
    }
    
    public func handleSelectionConfirmation() {
        guard !addedEvents.isEmpty else {
            cancelMultipleChanges()
            return
        }
        prepareAddEditEventBatchViewModel()
    }
    
    public func commitPendingBatch() {
        guard let eventBatch = addEditBatchListViewModel.addEditEventBatchModel.eventBatch else { return }
        addEditBatchListViewModel.addEditEventBatchModel.eventBatch = nil
        let batchKey = key(for: eventBatch)
        originalBatches.removeAll(where: { key(for: $0) == batchKey })
        if !eventBatch.events.isEmpty {
            originalBatches.append(eventBatch)
        }
        updateYearModel(with: originalEvents)
        save(for: calendarid)
        refreshBatchListIfVisible()
    }

    private func refreshBatchListIfVisible() {
        guard let selectedDay = addEditBatchListViewModel.selectedDay else { return }
        prepareAddEditBatchListViewModel(with: [selectedDay])
    }
    
    public func cancelMultipleChanges() {
        updateYearModel(with: originalEvents)
        daySelectionManager.toggleSelectionMode()
        addedEvents = []
        selectedColor = nil
    }
    
    public func prepareAddEditBatchListViewModel(with selectedDays: Set<Date>) {
        guard let selectedDay = selectedDays.first else {
            addEditBatchListViewModel.reset()
            return
        }
        let dayBatches = originalBatches.filter { batch in
            batch.events.contains { event in
                isSameDay(event.date, selectedDay)
            } || (batch.date.map { isSameDay($0, selectedDay) } ?? false)
        }
        addEditBatchListViewModel.prepare(with: dayBatches, and: selectedDay)
    }
    
    public func onBatchListDismissed() {
        daySelectionManager.selectedDays = []
        addEditBatchListViewModel.reset()
    }
    
    public func deleteBatches(_ batches: [EventBatchDataSource], for calendarId: Int64) {
        for batch in batches {
            originalBatches.removeAll(where: { key(for: $0) == key(for: batch) })
        }
        updateYearModel(with: originalEvents)
        save(for: calendarId)
        prepareAddEditBatchListViewModel(with: daySelectionManager.selectedDays)
    }
    
    public func reset() {
        label = ""
        state = .empty
        addEditBatchListViewModel.reset()
    }
    
    public func resetSelectedDays() {
        daySelectionManager.selectedDays = []
        if daySelectionManager.selectionMode == .multiple {
            commitPendingBatch()
            daySelectionManager.toggleSelectionMode()
            addedEvents = []
            selectedColor = nil
            updateYearModel(with: originalEvents)
        } else {
            commitPendingBatch()
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
        let eventColorsByDay = colorsByStartOfDay(from: events)
        let batchColorsByDay = batchColorsByStartOfDay()
        yearModel.months.forEach { month in
            month.weeks.forEach { week in
                week.days
                    .filter { day in
                        day.isInCurrentMonth
                    }
                    .forEach { day in
                        guard let dayDate = day.date else { return }
                        let key = Calendar.autoupdatingCurrent.startOfDay(for: dayDate)
                        let newEvents = (eventColorsByDay[key] ?? []) + (batchColorsByDay[key] ?? [])
                        guard day.events != newEvents else { return }
                        day.events = newEvents
                    }
            }
        }
    }
    
    private func updateDayModel(at date: Date, with events: Set<EventDataSource>) {
        guard let day = dayModel(for: date) else { return }
        let key = Calendar.autoupdatingCurrent.startOfDay(for: date)
        let newEvents = (colorsByStartOfDay(from: events)[key] ?? []) + (batchColorsByStartOfDay()[key] ?? [])
        guard day.events != newEvents else { return }
        day.events = newEvents
    }
    
    private func dayModel(for date: Date) -> PCCalendarDayModel? {
        var fallback: PCCalendarDayModel?
        for month in yearModel.months {
            for week in month.weeks {
                for day in week.days {
                    guard let dayDate = day.date, isSameDay(dayDate, date) else { continue }
                    if day.isInCurrentMonth { return day }
                    fallback = day
                }
            }
        }
        return fallback
    }
    
    private func colorsByStartOfDay(from events: Set<EventDataSource>) -> [Date: [String]] {
        var result: [Date: [String]] = [:]
        for event in events {
            result[Calendar.autoupdatingCurrent.startOfDay(for: event.date), default: []].append(event.color)
        }
        return result
    }
    
    private func batchColorsByStartOfDay() -> [Date: [String]] {
        var result: [Date: [String]] = [:]
        for batch in originalBatches {
            guard let batchDate = batch.date, !batch.colorName.isEmpty else { continue }
            result[Calendar.autoupdatingCurrent.startOfDay(for: batchDate), default: []].append(batch.colorName)
        }
        return result
    }
}
