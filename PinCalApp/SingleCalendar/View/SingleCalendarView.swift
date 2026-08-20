//
//  SingleCalendarView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 04.02.2026.
//

import SwiftUI
import ObjectBox

struct SingleCalendarView: View {
    @Bindable var viewModel: SingleCalendarModel
    
    @State private var columnCountSaveTask: Task<Void, Never>?
        
    var body: some View {
        ZStack {
            SingleCalendarStateView(state: viewModel.state) {
                AnyView(
                    SingleCalendarFrameView {
                        SingleCalendarCalendarContent(
                            isMultiSelect: viewModel.daySelectionManager.selectionMode == .multiple,
                            selectedColor: $viewModel.selectedColor,
                            isColorPickerDisabled: viewModel.isColorPickerDisabled,
                            yearModel: viewModel.yearModel
                        )
                    }
                    .onChange(of: viewModel.yearModel.numberOfColumns) {
                        if $0 != $1 {
                            scheduleColumnCountSave()
                        }
                    }
                    .onChange(of: viewModel.daySelectionManager.selectedDays) { _, newValue in
                        if viewModel.daySelectionManager.selectionMode == .multiple, let selectedDay = newValue.first {
                            if let selectedColor = viewModel.selectedColor {
                                viewModel.changeEvent(.init(name: "Event1", date: selectedDay, color: selectedColor.colorName))
                            }
                        } else if let selectedDay = newValue.first {
                            if viewModel.hasEvents(on: selectedDay) {
                                viewModel.prepareAddEditBatchListViewModel(with: newValue)
                            } else {
                                viewModel.prepareAddEditEventBatchViewModel(for: selectedDay)
                            }
                        }
                    }
                    .onChange(of: viewModel.isEditPresented) { oldValue, newValue in
                        if oldValue != newValue, !newValue {
                            viewModel.onBatchListDismissed()
                        }
                    }
                    .onChange(of: viewModel.isEditScreenPresented) { oldValue, newValue in
                        if oldValue != newValue, !newValue {
                            viewModel.resetSelectedDays()
                        }
                    }
                    .onChange(of: viewModel.addEditBatchListViewModel.eventBatchesToDelete) {
                        if $0 != $1 {
                            viewModel.deleteBatches($1, for: viewModel.calendarid)
                        }
                    }
                )
            }
            .padding(6)
            .navigationTitle(viewModel.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .id(viewModel.calendarid)
        }
        .ignoresSafeArea(edges: .bottom)
        .task(id: viewModel.calendarid) {
            await viewModel.fetch()
        }
        .onDisappear {
            flushColumnCountSave()
        }
        .navigationDestination(isPresented: $viewModel.isEditPresented) {
            AddEditEventBatchListView(
                viewModel: viewModel.addEditBatchListViewModel
            )
        }
        .navigationDestination(isPresented: $viewModel.isEditScreenPresented) {
            AddEditEventBatchScreen(
                viewModel: viewModel.addEditBatchListViewModel.addEditEventBatchModel
            )
        }
        .onChange(of: viewModel.addEditBatchListViewModel.addEditEventBatchModel.isPresented) { oldValue, newValue in
            if oldValue != newValue, !newValue {
                viewModel.resetSelectedDays()
            }
        }
    }
    
    private func scheduleColumnCountSave() {
        columnCountSaveTask?.cancel()
        columnCountSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            viewModel.save(for: viewModel.calendarid)
        }
    }
    
    private func flushColumnCountSave() {
        guard columnCountSaveTask != nil else { return }
        columnCountSaveTask?.cancel()
        columnCountSaveTask = nil
        viewModel.save(for: viewModel.calendarid)
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !viewModel.isEditPresented && !viewModel.isEditScreenPresented {
            ToolbarItem {
                Button(
                    viewModel.daySelectionManager.selectionMode == .multiple ? "Save" : "Multiselect",
                    systemImage: viewModel.daySelectionManager.selectionMode == .multiple ? "checkmark" : "plus.rectangle.on.rectangle"
                ) {
                    if viewModel.daySelectionManager.selectionMode == .multiple {
                        viewModel.handleSelectionConfirmation()
                    } else {
                        viewModel.daySelectionManager.toggleSelectionMode()
                    }
                }
            }
        }
    }
}

#Preview {
    SingleCalendarViewPreview()
}

private struct SingleCalendarViewPreview: View {
    @State private var model: SingleCalendarModel?
    
    var body: some View {
        NavigationStack {
            if let model {
                SingleCalendarView(viewModel: model)
            } else {
                PCProgressView(label: "Loading")
                    .task {
                        await loadModel()
                    }
            }
        }
    }
    
    @MainActor
    private func loadModel() async {
        let store = try! Store(directoryPath: "memory:single-calendar-preview-\(UUID().uuidString)")
        let calendarBox = store.box(for: PPCalendar.self)
        let calendar = PPCalendar(
            name: "Test Calendar",
            year: Calendar.current.component(.year, from: Date()),
            numberOfColumns: 2
        )
        try! calendarBox.put(calendar)
        
        let events = [
            PPEvent(name: "Event1", color: PCColorOption.option1.colorName, date: someDate(daysFromNow: -2)),
            PPEvent(name: "Event2", color: PCColorOption.option2.colorName, date: someDate(daysFromNow: 0)),
            PPEvent(name: "Event3", color: PCColorOption.option3.colorName, date: someDate(daysFromNow: 5))
        ]
        let eventBox = store.box(for: PPEvent.self)
        try! eventBox.put(events)
        
        let batch = PPEventBatch(title: "Women Cycle", color: PCColorOption.option1.colorName)
        let batchBox = store.box(for: PPEventBatch.self)
        try! batchBox.put(batch)
        batch.events.replace(events)
        try! batch.events.applyToDb()
        
        let savedCalendar = try! calendarBox.get(calendar.id)!
        savedCalendar.eventBatches.append(batch)
        try! savedCalendar.eventBatches.applyToDb()
        
        let manager = CalendarManager(service: ObjectBoxCalendarStorage(store: store))
        let loadedModel = SingleCalendarModel(calendarid: Int64(calendar.id), manager: manager)
        await loadedModel.fetch()
        model = loadedModel
    }
    
    private func someDate(daysFromNow: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date()) ?? Date()
    }
}
