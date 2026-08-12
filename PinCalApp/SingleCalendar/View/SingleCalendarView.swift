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
            content
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
        .navigationDestination(isPresented: $viewModel.isEditScreenPresented) {
            AddEditEventBatchScreen(
                viewModel: viewModel.addEditBatchListViewModel.addEditEventBatchModel,
                onSave: { viewModel.isEditScreenPresented = false },
                onCancel: { viewModel.isEditScreenPresented = false }
            )
        }
        .sheet(isPresented: $viewModel.isEditPresented) {
            editorContent
        }
    }
    
    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .empty:
            EmptyView()
        case .loading:
            DSProgressView(label: "Loading")
        case .content:
            contentView
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
        }
    }
    
    private var contentView: some View {
        calendarContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var calendarContent: some View {
        VStack(spacing: 0) {
            if viewModel.daySelectionManager.selectionMode == .multiple {
                ColorPickerView(selectedColor: $viewModel.selectedColor, style: .expanded)
                    .disabled(viewModel.isColorPickerDisabled)
            }
            USCalendarYearView(
                viewModel: viewModel.yearModel
            )
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
    
    private var editorContent: some View {
        AddEditEventBatchListView(
            viewModel: viewModel.addEditBatchListViewModel,
            onClose: { viewModel.isEditPresented = false },
            onBatchTap: { viewModel.routeToBatchEditor() }
        )
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
                DSProgressView(label: "Loading")
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
            PPEvent(name: "Event1", color: ColorOption.option1.colorName, date: someDate(daysFromNow: -2)),
            PPEvent(name: "Event2", color: ColorOption.option2.colorName, date: someDate(daysFromNow: 0)),
            PPEvent(name: "Event3", color: ColorOption.option3.colorName, date: someDate(daysFromNow: 5))
        ]
        let eventBox = store.box(for: PPEvent.self)
        try! eventBox.put(events)
        
        let batch = PPEventBatch(title: "Women Cycle", color: ColorOption.option1.colorName)
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
