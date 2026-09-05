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
    
    private(set) var originalBatches: [EventBatchDataSource] = []
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
    
    public private(set) var yearModel = PCCalendarYearModel()

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
        let result = originalBatches.contains { batch in
            batch.events.contains { event in
                isSameDay(event.date, date)
            } || (batch.date.map { isSameDay($0, date) } ?? false)
        }
        print("[PC] hasEvents(on: \(date)) = \(result) (originalBatches=\(originalBatches.count))")
        return result
    }

    /// Decides where navigation should go for a day-selection change. The batch
    /// list/editor views prepare their own view models; here we only stage the
    /// events for a new batch into the shared manager when needed. Returns `nil`
    /// when no navigation is needed.
    public func route(for selectedDays: Set<Date>) -> AppRoute? {
        print("[PC] route(for:) selectedDays=\(selectedDays) mode=\(daySelectionManager.selectionMode) hasEvents=\(selectedDays.first.map { hasEvents(on: $0) } ?? false)")
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
                isSameDay(event.date, day)
            } || (batch.date.map { isSameDay($0, day) } ?? false)
        }
    }

    public func batch(withId id: Int64) -> EventBatchDataSource? {
        originalBatches.first { $0.id == id }
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
        AddEditEventBatchViewModel(eventsSelectionManager: eventsSelectionManager)
    }

    public init(
        calendarid: Int64,
        cache: CalendarCache,
        eventsSelectionManager: PCEventsSelectionManager = PCEventsSelectionManager(),
        daySelectionManager: PCCalendarDaySelectionManager = PCCalendarDaySelectionManager()
    ) {
        self.calendarid = calendarid
        self.cache = cache
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
        // Mirror the calendar's column count onto the shared batch-editing
        // session manager so the batch editor's calendar uses the same layout
        // (and honors `-UITestColumns`), keeping its day cells reliably tappable.
        eventsSelectionManager.numberOfColumns = Self.initialNumberOfColumns(for: calendar)
        // Build the year model only once. Rebuilding it on every fetch would
        // swap out the PCCalendarDayModel instances the views are bound to,
        // so event updates would not be observed and committed days would
        // silently stop rendering. Event changes are applied in-place below.
        if yearModel.months.isEmpty {
            yearModel.months = dataProvider.months(forYear: calendar.year).map {
                PCCalendarMonthModel(dto: $0, daySelectionManager: daySelectionManager)
            }
            yearModel.numberOfCurrentMonth = dataProvider.numberOfCurrentMonth
            yearModel.set(initialNumberOfColumns: Self.initialNumberOfColumns(for: calendar))
        }
        
        originalBatches = calendar.eventBatches
        updateYearModel(with: originalEvents)
        state = .content
    }

    /// Resolves the year-grid column count for this calendar.
    ///
    /// UI tests can force a specific column count (e.g. a single column so the
    /// day cells are large and reliably tappable) by passing
    /// `-UITestColumns <n>` as a launch argument. It is ignored outside UI tests
    /// and does not affect the app's pinch-to-zoom (the `maximumNumberOfColumns`
    /// cap is unchanged).
    private static func initialNumberOfColumns(for calendar: CalendarDataSource) -> Int {
        forcedColumnsForUITests ?? calendar.numberOfColumns
    }

    private static var forcedColumnsForUITests: Int? {
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let flagIndex = arguments.firstIndex(of: "-UITestColumns"),
            arguments.indices.contains(flagIndex + 1),
            let value = Int(arguments[flagIndex + 1])
        else { return nil }
        return value
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

    /// Commits a batch that was edited/saved in the batch editor. The editor
    /// hands the resulting batch up through its `onCommit` closure; the batch
    /// view models are owned by their views and communicate with this model
    /// only through the shared managers.
    public func commitPendingBatch(_ eventBatch: EventBatchDataSource?) {
        print("[PC] commitPendingBatch mode=\(daySelectionManager.selectionMode) events=\(eventBatch?.events.map { $0.date } ?? []) name=\(eventBatch?.name ?? "")")
        guard let eventBatch else { return }
        let batchKey = key(for: eventBatch)
        originalBatches.removeAll(where: { key(for: $0) == batchKey })
        if !eventBatch.events.isEmpty {
            originalBatches.append(eventBatch)
        }
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
        for batch in batches {
            originalBatches.removeAll(where: { key(for: $0) == key(for: batch) })
        }
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
    
    enum BatchMergeKey: Hashable {
        case persisted(Int64)
        case pending(UUID)
        case unsaved(Int)
    }
    
    func key(for batch: EventBatchDataSource) -> BatchMergeKey {
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
        yearModel.months.forEach { month in
            month.weeks.forEach { week in
                week.days
                    .filter { day in
                        day.isInCurrentMonth
                    }
                    .forEach { day in
                        guard let dayDate = day.date else { return }
                        let key = Calendar.autoupdatingCurrent.startOfDay(for: dayDate)
                        let newEvents = eventColorsByDay[key] ?? []
                        guard day.events != newEvents else { return }
                        day.events = newEvents
                    }
            }
        }
    }
    
    private func updateDayModel(at date: Date, with events: Set<EventDataSource>) {
        guard let day = dayModel(for: date) else { return }
        let key = Calendar.autoupdatingCurrent.startOfDay(for: date)
        let newEvents = colorsByStartOfDay(from: events)[key] ?? []
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
    
}
