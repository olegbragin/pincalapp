//
//  EventBatchCreationTests.swift
//  PinCalAppTests
//
//  Created by Oleg Bragin on 04.08.2026.
//

import Testing
import Foundation
import ObjectBox
import CorePersistence
import DSKit
@testable import PinCalApp

@MainActor
struct EventBatchCreationTests {
    
    // MARK: - Helpers
    
    private func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)!
    }
    
    private func event(_ name: String = "Event1", day: Int, color: String = "eventColorOption1", timestamp: UUID? = nil) -> EventDataSource {
        .init(name: name, date: date(year: 2026, month: 6, day: day), color: color, timestamp: timestamp)
    }
    
    private func waitForBatchCount(_ expected: Int, in store: Store, timeout: TimeInterval = 3) async throws -> Bool {
        let batchBox = store.box(for: PPEventBatch.self)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try batchBox.all().count >= expected { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return try batchBox.all().count >= expected
    }
    
    // MARK: - AddEditListViewModel
    
    @Test func prepareAssignsUniqueTimestampsAndSortsByDate() {
        let viewModel = AddEditListViewModel()
        let later = event("B", day: 15, timestamp: nil)
        let earlier = event("A", day: 3, timestamp: nil)
        
        viewModel.prepare(with: [later, earlier])
        
        #expect(viewModel.events.map(\.name) == ["A", "B"])
        let timestamps = viewModel.events.compactMap(\.timestamp)
        #expect(timestamps.count == 2)
        #expect(Set(timestamps).count == 2)
    }
    
    @Test func prepareKeepsExistingTimestamps() {
        let viewModel = AddEditListViewModel()
        let timestamp = UUID()
        viewModel.prepare(with: [event(day: 3, timestamp: timestamp)])
        
        #expect(viewModel.events[0].timestamp == timestamp)
    }
    
    @Test func applyReplacesSingleEventByTimestamp() {
        let viewModel = AddEditListViewModel()
        viewModel.prepare(with: [event(day: 3), event(day: 4)])
        let edited = viewModel.events[0]
        
        viewModel.prepareAddEditViewModel(with: edited)
        viewModel.addEditEventModel.selectedColor = .option3
        #expect(viewModel.addEditEventModel.save())
        viewModel.apply(with: viewModel.addEditEventModel.event!)
        
        let colors = viewModel.events.map(\.color)
        #expect(colors[0] == "eventColorOption3")
        #expect(colors[1] == "eventColorOption1")
        #expect(viewModel.events.count == 2)
    }
    
    @Test func applyAppendsWhenNoTimestampMatches() {
        let viewModel = AddEditListViewModel()
        viewModel.prepare(with: [event(day: 3)])
        let stranger = event("X", day: 5, timestamp: UUID())
        
        viewModel.apply(with: stranger)
        
        #expect(viewModel.events.count == 2)
        #expect(viewModel.events.last == stranger)
    }
    
    @Test func recolorAllRecolorsEveryEventPreservingOtherFields() {
        let viewModel = AddEditListViewModel()
        viewModel.prepare(with: [event(day: 3), event(day: 4, color: "eventColorOption2")])
        
        viewModel.recolorAll(to: "eventColorOption4")
        
        #expect(viewModel.events.allSatisfy { $0.color == "eventColorOption4" })
        #expect(viewModel.events.map(\.date) == viewModel.events.sorted(by: { $0.date < $1.date }).map(\.date))
        #expect(viewModel.events.allSatisfy { $0.timestamp != nil })
    }
    
    @Test func prepareAddEditViewModelPopulatesEditor() {
        let viewModel = AddEditListViewModel()
        viewModel.prepare(with: [event(day: 3, color: "eventColorOption2")])
        
        viewModel.prepareAddEditViewModel(with: viewModel.events[0])
        
        #expect(viewModel.editingEvent != nil)
        #expect(viewModel.addEditEventModel.eventName == "Event1")
        #expect(viewModel.addEditEventModel.selectedColor == .option2)
        #expect(viewModel.addEditEventModel.selectedDate == viewModel.events[0].date)
        #expect(viewModel.addEditEventModel.timestamp == viewModel.events[0].timestamp)
    }
    
    // MARK: - AddEditEventBatchViewModel
    
    @Test func batchSaveCreatesBatchWithNameColorAndEvents() {
        let viewModel = AddEditEventBatchViewModel(events: [event(day: 3), event(day: 4)])
        viewModel.eventBatchName = "Women Cycle"
        viewModel.selectedColor = .option1
        
        #expect(viewModel.save())
        
        let batch = viewModel.eventBatch
        #expect(batch != nil)
        #expect(batch?.name == "Women Cycle")
        #expect(batch?.colorName == "eventColorOption1")
        #expect(batch?.events.count == 2)
    }
    
    @Test func batchSaveFailsWithoutName() {
        let viewModel = AddEditEventBatchViewModel(events: [event(day: 3)])
        viewModel.eventBatchName = ""
        viewModel.selectedColor = .option1
        
        #expect(!viewModel.save())
        #expect(viewModel.eventBatch == nil)
    }
    
    @Test func batchSaveFailsWithoutColor() {
        let viewModel = AddEditEventBatchViewModel(events: [event(day: 3)])
        viewModel.eventBatchName = "Women Cycle"
        viewModel.selectedColor = nil
        
        #expect(!viewModel.save())
        #expect(viewModel.eventBatch == nil)
    }
    
    @Test func defaultColorDerivesFromPassedEventsWhenNoColorSelected() {
        let viewModel = AddEditEventBatchViewModel(events: [event(day: 3, color: "eventColorOption2")])
        viewModel.selectedColor = nil
        
        #expect(viewModel.defaultColor == .option2)
    }
    
    @Test func defaultColorFallsBackToNilWithoutEventsOrColor() {
        let viewModel = AddEditEventBatchViewModel()
        viewModel.selectedColor = nil
        
        #expect(viewModel.defaultColor == nil)
    }
    
    @Test func canSaveRequiresNameAndColor() {
        let viewModel = AddEditEventBatchViewModel(events: [event(day: 3)])
        
        viewModel.eventBatchName = ""
        viewModel.selectedColor = nil
        #expect(!viewModel.canSave)
        
        viewModel.eventBatchName = "Women Cycle"
        #expect(!viewModel.canSave)
        
        viewModel.selectedColor = .option1
        #expect(viewModel.canSave)
    }
    
    @Test func recolorAllEventsRecolorsToSelectedBatchColor() {
        let viewModel = AddEditEventBatchViewModel(events: [event(day: 3, color: "eventColorOption2"), event(day: 4, color: "eventColorOption3")])
        viewModel.selectedColor = .option1
        
        viewModel.recolorAllEvents()
        
        #expect(viewModel.addEditListViewModel.events.allSatisfy { $0.color == "eventColorOption1" })
    }
    
    @Test func batchSavePreservesPerEventColorOverride() {
        let viewModel = AddEditEventBatchViewModel(events: [event(day: 3), event(day: 4)])
        viewModel.eventBatchName = "Cycle"
        viewModel.selectedColor = .option1
        viewModel.recolorAllEvents()
        
        let first = viewModel.addEditListViewModel.events[0]
        viewModel.addEditListViewModel.prepareAddEditViewModel(with: first)
        viewModel.addEditListViewModel.addEditEventModel.selectedColor = .option3
        #expect(viewModel.addEditListViewModel.addEditEventModel.save())
        viewModel.addEditListViewModel.apply(with: viewModel.addEditListViewModel.addEditEventModel.event!)
        
        #expect(viewModel.save())
        
        let events = viewModel.eventBatch!.events
        #expect(events[0].color == "eventColorOption3")
        #expect(events[1].color == "eventColorOption1")
    }
    
    @Test func batchResetClearsEventBatch() {
        let viewModel = AddEditEventBatchViewModel(events: [event(day: 3)])
        viewModel.eventBatchName = "Cycle"
        viewModel.selectedColor = .option1
        _ = viewModel.save()
        #expect(viewModel.eventBatch != nil)
        
        viewModel.reset()
        
        #expect(viewModel.eventBatch == nil)
        #expect(viewModel.eventBatchName == "")
        #expect(viewModel.selectedColor == nil)
    }
    
    @Test func batchTitleShowsPeriodFromEarliestToLatestEvent() {
        let viewModel = AddEditEventBatchViewModel(events: [event(day: 20), event(day: 10)])
        
        #expect(viewModel.preferredTitle == "10 Jun 2026 - 20 Jun 2026")
    }
    
    @Test func batchTitleShowsSingleEventDate() {
        let viewModel = AddEditEventBatchViewModel(events: [event(day: 10)])
        
        #expect(viewModel.preferredTitle == "10 Jun 2026")
    }
    
    @Test func batchTitleFallsBackToSelectedDayDateWithoutEvents() {
        let viewModel = AddEditEventBatchViewModel()
        viewModel.date = date(year: 2026, month: 6, day: 10)
        
        #expect(viewModel.preferredTitle == "10 Jun 2026")
    }
    
    @Test func batchTitleIsNilWithoutEventsOrSelectedDay() {
        let viewModel = AddEditEventBatchViewModel()
        
        #expect(viewModel.preferredTitle == nil)
    }
    
    @Test func setupCalendarSetsScrollTargetToEarliestEvent() {
        let viewModel = AddEditEventBatchViewModel(events: [event(day: 20), event(day: 10)])
        
        #expect(viewModel.yearModel.scrollTargetDate.map { Calendar.current.component(.day, from: $0) } == 10)
    }
    
    @Test func setupCalendarFallsBackScrollTargetToSelectedDay() {
        let viewModel = AddEditEventBatchViewModel()
        viewModel.date = date(year: 2026, month: 1, day: 1)
        viewModel.setupCalendar()
        
        #expect(viewModel.yearModel.scrollTargetDate.map { Calendar.current.component(.day, from: $0) } == 1)
    }
    
    // MARK: - SingleCalendarModel
    
    @Test func colorPickerDisabledInMultipleModeWithColorAndEvents() {
        let model = SingleCalendarModel(calendarid: 0, cache: CalendarCache(manager: CalendarManager()))
        model.selectedColor = .option1
        model.daySelectionManager.selectionMode = .multiple
        model.changeEvent(event(day: 3))
        
        #expect(model.isColorPickerDisabled)
    }
    
    @Test func colorPickerEnabledWhenNoColorSelected() {
        let model = SingleCalendarModel(calendarid: 0, cache: CalendarCache(manager: CalendarManager()))
        model.selectedColor = nil
        model.daySelectionManager.selectionMode = .multiple
        model.changeEvent(event(day: 3))
        
        #expect(!model.isColorPickerDisabled)
    }
    
    @Test func colorPickerEnabledWhenNoEventsAddedYet() {
        let model = SingleCalendarModel(calendarid: 0, cache: CalendarCache(manager: CalendarManager()))
        model.selectedColor = .option1
        model.daySelectionManager.selectionMode = .multiple
        
        #expect(!model.isColorPickerDisabled)
    }
    
    @Test func colorPickerEnabledInSingleMode() {
        let model = SingleCalendarModel(calendarid: 0, cache: CalendarCache(manager: CalendarManager()))
        model.selectedColor = .option1
        model.daySelectionManager.selectionMode = .single
        model.changeEvent(event(day: 3))
        
        #expect(!model.isColorPickerDisabled)
    }
    
    @Test func prepareAddEditEventBatchViewModelPopulatesEditorFromAddedEvents() {
        let model = SingleCalendarModel(calendarid: 0, cache: CalendarCache(manager: CalendarManager()))
        model.selectedColor = .option1
        model.changeEvent(event(day: 3))
        model.changeEvent(event(day: 5))
        model.daySelectionManager.selectionMode = .multiple
        
        model.prepareAddEditEventBatchViewModel()
        
        let addEdit = model.addEditBatchListViewModel.addEditEventBatchModel
        #expect(addEdit.eventBatchName == "Event1")
        #expect(addEdit.selectedColor == .option1)
        #expect(addEdit.addEditListViewModel.events.count == 2)
        #expect(addEdit.addEditListViewModel.events.map(\.date) == addEdit.addEditListViewModel.events.sorted(by: { $0.date < $1.date }).map(\.date))
        #expect(addEdit.timestamp != nil)
    }
    
    @Test func prepareAddEditEventBatchViewModelDoesNothingWithoutEvents() {
        let model = SingleCalendarModel(calendarid: 0, cache: CalendarCache(manager: CalendarManager()))
        model.daySelectionManager.selectionMode = .multiple
        
        model.prepareAddEditEventBatchViewModel()
        
        #expect(model.addEditBatchListViewModel.addEditEventBatchModel.eventBatch == nil)
    }
    
    @Test func cancelMultipleChangesExitsModeAndClearsState() {
        let model = SingleCalendarModel(calendarid: 0, cache: CalendarCache(manager: CalendarManager()))
        model.selectedColor = .option1
        model.daySelectionManager.selectionMode = .multiple
        model.changeEvent(event(day: 3))
        #expect(model.isColorPickerDisabled)
        
        model.cancelMultipleChanges()
        
        #expect(model.daySelectionManager.selectionMode == .single)
        #expect(!model.isColorPickerDisabled)
    }
    
    @Test func resetSelectedDaysExitsMultipleModeWhenSheetDismissed() {
        let model = SingleCalendarModel(calendarid: 0, cache: CalendarCache(manager: CalendarManager()))
        model.selectedColor = .option1
        model.daySelectionManager.selectionMode = .multiple
        model.changeEvent(event(day: 3))
        
        model.resetSelectedDays()
        
        #expect(model.daySelectionManager.selectionMode == .single)
        #expect(model.daySelectionManager.selectedDays.isEmpty)
        #expect(!model.isColorPickerDisabled)
    }
    
    @Test func commitNewBatchPersistsBatchWithEditedNameColorAndPerEventOverride() async throws {
        let store = try! Store(directoryPath: "memory:commit-\(UUID().uuidString)")
        defer { store.close() }
        
        let calendarBox = store.box(for: PPCalendar.self)
        let calendar = PPCalendar(name: "Test", year: 2026, numberOfColumns: 3)
        try calendarBox.put(calendar)
        
        let manager = CalendarManager(service: ObjectBoxCalendarStorage(store: store))
        let cache = CalendarCache(manager: manager)
        let model = SingleCalendarModel(calendarid: Int64(calendar.id), cache: cache)
        await model.fetch(force: true)
        #expect(model.state == .content)
        
        model.selectedColor = .option1
        model.changeEvent(event(day: 10))
        model.changeEvent(event(day: 11))
        model.daySelectionManager.selectionMode = .multiple
        
        model.prepareAddEditEventBatchViewModel()
        let addEdit = model.addEditBatchListViewModel.addEditEventBatchModel
        addEdit.eventBatchName = "Women Cycle"
        addEdit.selectedColor = .option1
        addEdit.recolorAllEvents()
        
        let first = addEdit.addEditListViewModel.events[0]
        addEdit.addEditListViewModel.prepareAddEditViewModel(with: first)
        addEdit.addEditListViewModel.addEditEventModel.selectedColor = .option3
        #expect(addEdit.addEditListViewModel.addEditEventModel.save())
        addEdit.addEditListViewModel.apply(with: addEdit.addEditListViewModel.addEditEventModel.event!)
        
        #expect(addEdit.save())
        model.resetSelectedDays()
        
        #expect(model.daySelectionManager.selectionMode == .single)
        #expect(!model.isColorPickerDisabled)
        
        #expect(try await waitForBatchCount(1, in: store))
        
        let batchBox = store.box(for: PPEventBatch.self)
        let eventBox = store.box(for: PPEvent.self)
        let persisted = try batchBox.all()[0]
        #expect(persisted.title == "Women Cycle")
        #expect(persisted.color == "eventColorOption1")
        
        let persistedEvents = Array(persisted.events).sorted { $0.date < $1.date }
        #expect(persistedEvents.count == 2)
        #expect(persistedEvents[0].color == "eventColorOption3")
        #expect(persistedEvents[1].color == "eventColorOption1")
        #expect(try eventBox.all().count == 2)
    }
    
    @Test func sheetDismissWithoutSaveDiscardsPendingBatch() async throws {
        let store = try! Store(directoryPath: "memory:discard-\(UUID().uuidString)")
        defer { store.close() }
        
        let calendarBox = store.box(for: PPCalendar.self)
        let calendar = PPCalendar(name: "Test", year: 2026, numberOfColumns: 3)
        try calendarBox.put(calendar)
        
        let manager = CalendarManager(service: ObjectBoxCalendarStorage(store: store))
        let cache = CalendarCache(manager: manager)
        let model = SingleCalendarModel(calendarid: Int64(calendar.id), cache: cache)
        await model.fetch(force: true)
        
        model.selectedColor = .option1
        model.changeEvent(event(day: 10))
        model.changeEvent(event(day: 11))
        model.daySelectionManager.selectionMode = .multiple
        
        model.prepareAddEditEventBatchViewModel()
        #expect(model.addEditBatchListViewModel.addEditEventBatchModel.eventBatch == nil)
        
        model.resetSelectedDays()
        
        #expect(model.daySelectionManager.selectionMode == .single)
        #expect(!model.isColorPickerDisabled)
        #expect(try store.box(for: PPEventBatch.self).all().isEmpty)
        #expect(try store.box(for: PPEvent.self).all().isEmpty)
    }
    
    @Test func committedBatchAppearsInDaySheet() async throws {
        let store = try! Store(directoryPath: "memory:daysheet-\(UUID().uuidString)")
        defer { store.close() }
        
        let calendarBox = store.box(for: PPCalendar.self)
        let calendar = PPCalendar(name: "Test", year: 2026, numberOfColumns: 3)
        try calendarBox.put(calendar)
        
        let manager = CalendarManager(service: ObjectBoxCalendarStorage(store: store))
        let cache = CalendarCache(manager: manager)
        let model = SingleCalendarModel(calendarid: Int64(calendar.id), cache: cache)
        await model.fetch(force: true)
        
        let day10 = date(year: 2026, month: 6, day: 10)
        model.selectedColor = .option1
        model.changeEvent(event(day: 10))
        model.changeEvent(event(day: 11))
        model.daySelectionManager.selectionMode = .multiple
        
        model.prepareAddEditEventBatchViewModel()
        let addEdit = model.addEditBatchListViewModel.addEditEventBatchModel
        addEdit.eventBatchName = "Women Cycle"
        addEdit.selectedColor = .option1
        addEdit.recolorAllEvents()
        #expect(addEdit.save())
        model.resetSelectedDays()
        
        model.prepareAddEditBatchListViewModel(with: [day10])
        
        let visibleBatches = model.addEditBatchListViewModel.eventBatches
        #expect(visibleBatches.count == 1)
        #expect(visibleBatches[0].name == "Women Cycle")
        #expect(visibleBatches[0].events.count == 2)
    }
    
    // MARK: - AddEditEventBatchScreen calendar toggling
    
    @Test func toggleEventAddsAndRemovesEventsOnBatchScreen() {
        let viewModel = AddEditEventBatchViewModel()
        viewModel.selectedColor = .option1
        let day10 = date(year: 2026, month: 6, day: 10)
        let day12 = date(year: 2026, month: 6, day: 12)
        
        viewModel.toggleEvent(on: day10)
        viewModel.toggleEvent(on: day12)
        viewModel.toggleEvent(on: day12)
        
        #expect(viewModel.addEditListViewModel.events.count == 1)
        #expect(viewModel.addEditListViewModel.hasEvent(on: day10))
        #expect(!viewModel.addEditListViewModel.hasEvent(on: day12))
        #expect(viewModel.daySelectionManager.selectedDays.isEmpty)
    }
    
    @Test func toggleEventColorsDaysOnBatchCalendar() {
        let viewModel = AddEditEventBatchViewModel()
        viewModel.selectedColor = .option1
        viewModel.toggleEvent(on: date(year: 2026, month: 6, day: 10))
        
        let dayModel = viewModel.yearModel.months
            .first(where: { $0.number == 6 })?
            .weeks
            .flatMap(\.days)
            .first(where: { day in
                guard let dayDate = day.date else { return false }
                return Calendar.current.isDate(dayDate, inSameDayAs: date(year: 2026, month: 6, day: 10))
            })
        #expect(dayModel?.events == ["eventColorOption1"])
    }
    
    @Test func toggleEventPrefersInMonthDayWhenDateSpansMonths() {
        let viewModel = AddEditEventBatchViewModel()
        viewModel.selectedColor = .option1
        let july2 = date(year: 2026, month: 7, day: 2)
        viewModel.toggleEvent(on: july2)
        
        let july2InMonth = viewModel.yearModel.months
            .first(where: { $0.number == 7 })?
            .weeks
            .flatMap(\.days)
            .first(where: { day in
                day.isInCurrentMonth && day.date.map { Calendar.current.isDate($0, inSameDayAs: july2) } == true
            })
        #expect(july2InMonth?.events == ["eventColorOption1"])
        
        let july2OutOfMonth = viewModel.yearModel.months
            .first(where: { $0.number == 6 })?
            .weeks
            .flatMap(\.days)
            .first(where: { day in
                !day.isInCurrentMonth && day.date.map { Calendar.current.isDate($0, inSameDayAs: july2) } == true
            })
        #expect(july2OutOfMonth?.events.isEmpty == true)
    }
    
    @Test func editingExistingBatchRemovesToggledOffEventsFromCalendar() async throws {
        let store = try! Store(directoryPath: "memory:edit-\(UUID().uuidString)")
        defer { store.close() }
        
        let calendarBox = store.box(for: PPCalendar.self)
        let calendar = PPCalendar(name: "Test", year: 2026, numberOfColumns: 3)
        try calendarBox.put(calendar)
        
        let day10 = date(year: 2026, month: 6, day: 10)
        let day12 = date(year: 2026, month: 6, day: 12)
        
        let batch = PPEventBatch(title: "Women Cycle", color: "eventColorOption1")
        let batchBox = store.box(for: PPEventBatch.self)
        try batchBox.put(batch)
        let events = [
            PPEvent(name: "Event1", color: "eventColorOption1", date: day10),
            PPEvent(name: "Event1", color: "eventColorOption1", date: day12)
        ]
        let eventBox = store.box(for: PPEvent.self)
        try eventBox.put(events)
        batch.events.replace(events)
        try batch.events.applyToDb()
        
        let savedCalendar = try calendarBox.get(calendar.id)!
        savedCalendar.eventBatches.append(batch)
        try savedCalendar.eventBatches.applyToDb()
        
        let manager = CalendarManager(service: ObjectBoxCalendarStorage(store: store))
        let cache = CalendarCache(manager: manager)
        let model = SingleCalendarModel(calendarid: Int64(calendar.id), cache: cache)
        await model.fetch(force: true)
        #expect(model.state == .content)
        
        model.prepareAddEditBatchListViewModel(with: [day10])
        let batchList = model.addEditBatchListViewModel
        #expect(batchList.eventBatches.count == 1)
        batchList.prepareAddEditBatchViewModel(with: batchList.eventBatches[0])
        
        let addEdit = batchList.addEditEventBatchModel
        #expect(addEdit.eventBatchId != 0)
        #expect(addEdit.addEditListViewModel.events.count == 2)
        
        addEdit.toggleEvent(on: day10)
        addEdit.toggleEvent(on: day12)
        #expect(addEdit.addEditListViewModel.events.isEmpty)
        
        #expect(addEdit.save())
        model.resetSelectedDays()
        
        let dayModel = model.yearModel.months
            .first(where: { $0.number == 6 })?
            .weeks
            .flatMap(\.days)
            .first(where: { day in
                guard let dayDate = day.date else { return false }
                return Calendar.current.isDate(dayDate, inSameDayAs: day10)
            })
        #expect(dayModel?.events.isEmpty == true)
        #expect(!model.hasEvents(on: day10))
        
        let storedBatches = store.box(for: PPEventBatch.self)
        let storedEvents = store.box(for: PPEvent.self)
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if try storedEvents.all().isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(try storedEvents.all().isEmpty)
        #expect(try storedBatches.all().isEmpty)
    }
    
    @Test func batchCreatedViaCalendarTogglesPersistsAndReflectsOnSingleCalendar() async throws {
        let store = try! Store(directoryPath: "memory:toggle-\(UUID().uuidString)")
        defer { store.close() }
        
        let calendarBox = store.box(for: PPCalendar.self)
        let calendar = PPCalendar(name: "Test", year: 2026, numberOfColumns: 3)
        try calendarBox.put(calendar)
        
        let manager = CalendarManager(service: ObjectBoxCalendarStorage(store: store))
        let cache = CalendarCache(manager: manager)
        let model = SingleCalendarModel(calendarid: Int64(calendar.id), cache: cache)
        await model.fetch(force: true)
        #expect(model.state == .content)
        
        model.prepareAddEditEventBatchViewModel(for: date(year: 2026, month: 6, day: 10))
        let addEdit = model.addEditBatchListViewModel.addEditEventBatchModel
        addEdit.eventBatchName = "Women Cycle"
        addEdit.selectedColor = .option1
        
        let day10 = date(year: 2026, month: 6, day: 10)
        let day12 = date(year: 2026, month: 6, day: 12)
        addEdit.toggleEvent(on: day12)
        addEdit.toggleEvent(on: day12)
        
        #expect(addEdit.save())
        model.resetSelectedDays()
        
        #expect(try await waitForBatchCount(1, in: store))
        
        let batchBox = store.box(for: PPEventBatch.self)
        let persisted = try batchBox.all()[0]
        #expect(persisted.title == "Women Cycle")
        #expect(persisted.color == "eventColorOption1")
        let persistedEvents = Array(persisted.events)
        #expect(persistedEvents.count == 1)
        #expect(Calendar.current.isDate(persistedEvents[0].date, inSameDayAs: day10))
        
        let dayModel = model.yearModel.months
            .first(where: { $0.number == 6 })?
            .weeks
            .flatMap(\.days)
            .first(where: { day in
                guard let dayDate = day.date else { return false }
                return Calendar.current.isDate(dayDate, inSameDayAs: day10)
            })
        #expect(dayModel?.events.contains("eventColorOption1") == true)
    }
    
    @Test func prepareAddEditEventBatchViewModelForDateCreatesBatchForDay() {
        let model = SingleCalendarModel(calendarid: 0, cache: CalendarCache(manager: CalendarManager()))
        let day10 = date(year: 2026, month: 6, day: 10)
        
        model.prepareAddEditEventBatchViewModel(for: day10)
        
        let addEdit = model.addEditBatchListViewModel.addEditEventBatchModel
        #expect(addEdit.selectedDays == [day10])
        #expect(addEdit.eventBatchName == "")
        #expect(addEdit.selectedColor == .option1)
        #expect(addEdit.date == day10)
        let events = addEdit.addEditListViewModel.events
        #expect(events.count == 1)
        #expect(events[0].name == "")
        #expect(events[0].color == "eventColorOption1")
        #expect(addEdit.addEditListViewModel.hasEvent(on: day10))
    }
}
