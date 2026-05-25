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
    private let manager = CalendarManager()
    
    private var originalEvents: Set<EventDataSource> = []
    private var addedEvents: Set<EventDataSource> = []
    
    private(set) var calendarid: Int64
    private(set) var label: String = ""
    
    let daySelectionManager = USCalendarDaySelectionManager()
    
    var selectedColor: ColorOption?
    
    private(set) var yearModel = USCalendarYearModel()
    private(set) var editListViewModel = EventListViewModel()
    
    var state: State = .empty
    var isEditSheetPresented = false
    var isLegendSheetPresented = false
    
    var selectedEvents: [EventDataSource] {
        guard !daySelectionManager.selectedDays.isEmpty else { return [] }
        return originalEvents.filter { event in
            daySelectionManager.selectedDays.contains { date in
                let dayDate = event.date
                let eventDateComponents = dataProvider.dateComponents(forDate: dayDate)
                let dayComponents = dataProvider.dateComponents(forDate: date)
                return
                    dayComponents.day == eventDateComponents.day &&
                    dayComponents.month == eventDateComponents.month &&
                    dayComponents.year == eventDateComponents.year
            }
        }
    }
    
    init(calendarid: Int64) {
        self.calendarid = calendarid
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
        
        originalEvents = Set(calendar.events)
        updateYearModel(with: originalEvents)
        state = .content
    }
    
    func save(for calendarId: Int64) {
        Task {
            guard var persistedCalendar = try? await self.manager.getCalendar(id: calendarId) else { return }
            persistedCalendar.numberOfColumns = yearModel.internalNumberOfColumns
            persistedCalendar.events = Array(originalEvents)
            try? await manager.updateCalendar(persistedCalendar)
            state = .content
        }
    }
    
    func commitMultipleChanges(for calendarId: Int64) {
        let allEvents = originalEvents.union(addedEvents)
        originalEvents = allEvents
        
        updateYearModel(with: allEvents)
        daySelectionManager.toggleSelectionMode()
        addedEvents = []
        save(for: calendarId)
    }
    
    func cancelMultipleChanges() {
        updateYearModel(with: originalEvents)
        daySelectionManager.toggleSelectionMode()
        addedEvents = []
    }
    
    func prepareEditListViewModel(with selectedDays: Set<Date>) {
        editListViewModel.prepare(with: selectedEvents, and: selectedDays.first)
        isEditSheetPresented = selectedDays.first != nil
    }
    
    func apply(events: [EventDataSource], action: Action, for calendarId: Int64) {
        switch action {
        case .change:
            let newEvents = mergeSetsByID(Set(originalEvents), with: Set(events))
            originalEvents = newEvents
            updateYearModel(with: originalEvents)
        case .delete:
            events.forEach {
                originalEvents.remove($0)
            }
            updateYearModel(with: originalEvents)
        }
        save(for: calendarId)
        prepareEditListViewModel(with: daySelectionManager.selectedDays)
    }
    
    func reset() {
        label = ""
        state = .empty
        isEditSheetPresented = false
        isLegendSheetPresented = false
        editListViewModel.reset()
    }
    
    func resetSelectedDays() {
        daySelectionManager.selectedDays = []
        editListViewModel.cancel()
    }
    
    private func mergeSetsByID<T: Hashable & Identifiable>(
        _ originalSet: Set<T>,
        with updates: Set<T>
    ) -> Set<T> {
        // Шаг 1: преобразуем исходный набор в словарь по ID
        var dictionary = Dictionary(uniqueKeysWithValues: originalSet.map { ($0.id, $0) })

        // Шаг 2: обновляем словарь объектами из updates — дубли по ID перезапишутся
        updates.forEach { update in
            dictionary[update.id] = update
        }

        // Шаг 3: возвращаем новый Set
        return Set(dictionary.values)
    }
    
    private func updateYearModel(with events: Set<EventDataSource>) {
        yearModel.months.forEach { month in
            month.weeks.forEach { week in
                week.days
                    .filter { day in
                        day.isInCurrentMonth
                    }
                    .forEach { day in
                        let dayEvents = events.filter {
                            guard let dayDate = day.date else { return false }
                            let eventDateComponents = dataProvider.dateComponents(forDate: $0.date)
                            let dayComponents = dataProvider.dateComponents(forDate: dayDate)
                            return
                                dayComponents.day == eventDateComponents.day &&
                                dayComponents.month == eventDateComponents.month &&
                                dayComponents.year == eventDateComponents.year
                        }
                        day.events = dayEvents.map {
                            $0.color
                        }
                    }
            }
        }
    }
}
