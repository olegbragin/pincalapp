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
    
    private let cache: CalendarCache
    private let dataProvider: PCCalendarDataProvider
    
    private(set) var originalBatches: [EventBatchDataSource] {
        get { eventsSelectionManager.batches }
        set { eventsSelectionManager.batches = newValue }
    }
    private var addedEvents: Set<EventDataSource> = []
    
    public private(set) var calendarid: Int64
    public private(set) var label: String = ""
    public private(set) var isArchived: Bool = false
    
    // Batch-editing session managers. Injected from outside (app root) and
    // shared across the main calendar and the batch views; all communication
    // about the batch session flows through them.
    public let eventsSelectionManager: PCEventsSelectionManager
    public let daySelectionManager: PCCalendarDaySelectionManager

    public var selectedColor: PCColorOption?
    
    public private(set) var yearModel = PCCalendarYearDataSource()

    public var state: State = .empty
    
    @ObservationIgnored private var cancellable: AnyCancellable?
    
    private var originalEvents: Set<EventDataSource> {
        Set(originalBatches.flatMap(\.events))
    }
    
    var selectedEvents: [EventDataSource] {
        guard !daySelectionManager.selectedDays.isEmpty else { return [] }
        return originalEvents.filter { event in
            daySelectionManager.selectedDays.contains { date in
                dataProvider.isSameDay(event.date, date)
            }
        }
    }
    
    public func hasEvents(on date: Date) -> Bool {
        let result = originalBatches.contains { batch in
            batch.events.contains { event in
                dataProvider.isSameDay(event.date, date)
            } || (batch.date.map { dataProvider.isSameDay($0, date) } ?? false)
        }
        return result
    }

    /// Decides where navigation should go for a day-selection change. The batch
    /// list/editor views prepare their own view models; here we only stage the
    /// events for a new batch into the shared manager when needed. Returns `nil`
    /// when no navigation is needed.
    public func route(for selectedDays: Set<Date>) -> AppRoute? {
        guard !isArchived, let day = selectedDays.first else { return nil }

        if daySelectionManager.selectionMode == .multiple {
            if let selectedColor {
                changeEvent(EventDataSource(name: "", date: day, color: selectedColor.colorName))
            }
            return nil
        }

        if hasEvents(on: day) {
            return .dayBatches(day)
        } else {
            prepareNewBatchEvents(on: day)
            return .batchEditor(.newDay(day))
        }
    }

    public func batches(for day: Date) -> [EventBatchDataSource] {
        originalBatches.filter { batch in
            batch.events.contains { event in
                dataProvider.isSameDay(event.date, day)
            } || (batch.date.map { dataProvider.isSameDay($0, day) } ?? false)
        }
    }

    public func batch(withId id: Int64) -> EventBatchDataSource? {
        eventsSelectionManager.batch(withId: id)
    }

    /// Resolves the batch to hand to the batch editor for a navigation source.
    /// Returns `nil` for a brand-new day (the editor seeds from the session).
    public func batch(for source: BatchEditorSource) -> EventBatchDataSource? {
        if case .existingBatch(let id) = source {
            return batch(withId: id)
        }
        return nil
    }

    /// Stages the single placeholder event for a new batch anchored on `date`
    /// into the shared manager.
    func prepareNewBatchEvents(on date: Date) {
        eventsSelectionManager.prepare(with: [
            EventDataSource(name: "", date: date, color: PCColorOption.option1.colorName)
        ])
    }

    /// Stages the events chosen via multi-select into the shared manager.
    func prepareAddEditEventBatchViewModel() {
        guard !addedEvents.isEmpty else { return }
        eventsSelectionManager.prepare(with: addedEvents.sorted { $0.date < $1.date })
    }

    /// Stages the single placeholder event for a new batch on `date`.
    func prepareAddEditEventBatchViewModel(for date: Date) {
        prepareNewBatchEvents(on: date)
    }

    /// Creates a batch editor view model bound to the shared session manager.
    public func makeBatchEditor() -> AddEditEventBatchViewModel {
        AddEditEventBatchViewModel(eventsSelectionManager: eventsSelectionManager, calendarId: calendarid)
    }

    public init(
        calendarid: Int64,
        cache: CalendarCache,
        dataProvider: PCCalendarDataProvider = PCCalendarDataProvider(),
        eventsSelectionManager: PCEventsSelectionManager = PCEventsSelectionManager(),
        daySelectionManager: PCCalendarDaySelectionManager = PCCalendarDaySelectionManager()
    ) {
        self.calendarid = calendarid
        self.cache = cache
        self.dataProvider = dataProvider
        self.eventsSelectionManager = eventsSelectionManager
        self.daySelectionManager = daySelectionManager
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
            yearModel = dataProvider.makeYearModel(
                year: calendar.year,
                numberOfColumns: calendar.numberOfColumns,
                daySelectionManager: daySelectionManager
            )
        }
        // Mirror the resolved column count onto the shared batch-editing session
        // manager so the batch editor's calendar uses the same layout (and honors
        // `-UITestColumns`), keeping its day cells reliably tappable.
        eventsSelectionManager.numberOfColumns = yearModel.numberOfColumns
        
        eventsSelectionManager.setCalendar(id: calendarid, batches: calendar.eventBatches)
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
    
    public func handleSelectionConfirmation() -> AppRoute? {
        guard !addedEvents.isEmpty else {
            cancelMultipleChanges()
            return nil
        }
        prepareAddEditEventBatchViewModel()
        guard let day = addedEvents.sorted(by: { $0.date < $1.date }).first?.date else { return nil }
        return .batchEditor(.newDay(day))
    }

    /// Commits a batch that was edited/saved in the batch editor. The manager
    /// owns the calendar's batch list and the persistence; this model only
    /// updates its own calendar state (year model + multi-select session).
    public func commitPendingBatch(_ eventBatch: EventBatchDataSource?) {
        eventsSelectionManager.commit(eventBatch)
        updateYearModel(with: originalEvents)
        save(for: calendarid)
        if daySelectionManager.selectionMode == .multiple {
            daySelectionManager.toggleSelectionMode()
            addedEvents = []
            selectedColor = nil
        }
    }
    
    public func cancelMultipleChanges() {
        updateYearModel(with: originalEvents)
        daySelectionManager.toggleSelectionMode()
        addedEvents = []
        selectedColor = nil
    }
    
    public func onBatchListDismissed() {
        daySelectionManager.selectedDays = []
        eventsSelectionManager.reset()
    }
    
    public func deleteBatches(_ batches: [EventBatchDataSource], for calendarId: Int64) {
        eventsSelectionManager.deleteBatches(batches)
        updateYearModel(with: originalEvents)
        save(for: calendarId)
    }
    
    public func reset() {
        label = ""
        state = .empty
        eventsSelectionManager.reset()
    }
    
    public func resetSelectedDays() {
        daySelectionManager.selectedDays = []
        eventsSelectionManager.reset()
        if daySelectionManager.selectionMode == .multiple {
            daySelectionManager.toggleSelectionMode()
            addedEvents = []
            selectedColor = nil
            updateYearModel(with: originalEvents)
        }
    }
    
    private func updateYearModel(with events: Set<EventDataSource>) {
        let eventColorsByDay = colorsByStartOfDay(from: events)
        yearModel.months.forEach { month in
            month.weeks.forEach { week in
                week.days
                    .filter { day in
                        day.isInCurrentMonth
                    }
                    .forEach { day in
                        guard let dayDate = day.date else { return }
                        let key = dataProvider.startOfDay(for: dayDate)
                        let newEvents = eventColorsByDay[key] ?? []
                        guard day.events != newEvents else { return }
                        day.events = newEvents
                    }
            }
        }
    }
    
    private func updateDayModel(at date: Date, with events: Set<EventDataSource>) {
        guard let day = dayModel(for: date) else { return }
        let key = dataProvider.startOfDay(for: date)
        let newEvents = colorsByStartOfDay(from: events)[key] ?? []
        guard day.events != newEvents else { return }
        day.events = newEvents
    }
    
    private func dayModel(for date: Date) -> PCCalendarDayModel? {
        var fallback: PCCalendarDayModel?
        for month in yearModel.months {
            for week in month.weeks {
                for day in week.days {
                    guard let dayDate = day.date, dataProvider.isSameDay(dayDate, date) else { continue }
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
            result[dataProvider.startOfDay(for: event.date), default: []].append(event.color)
        }
        return result
    }
    
}
