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
    @Environment(RootNavigation.self) var navigation
    
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
                        guard let route = viewModel.route(for: newValue) else { return }
                        navigation.push(route)
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
            .toolbarBackground(Color("colorBackgroundMain"), for: .navigationBar)
            .toolbar { toolbarContent }
            .id(viewModel.calendarid)
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .dayBatches:
                    AddEditEventBatchListView(
                        viewModel: viewModel.addEditBatchListViewModel
                    )
                case .batchEditor:
                    AddEditEventBatchScreen(
                        viewModel: viewModel.addEditBatchListViewModel.addEditEventBatchModel,
                        onCommit: { viewModel.commitPendingBatch() }
                    )
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .task(id: viewModel.calendarid) {
            await viewModel.fetch()
        }
        .onDisappear {
            flushColumnCountSave()
        }
        .onChange(of: navigation.isAtRoot) { _, isAtRoot in
            if isAtRoot {
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
        if navigation.isAtRoot, !viewModel.isArchived {
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
        
        let loadedModel = SingleCalendarModel(calendarid: Int64(calendar.id), cache: CalendarCache(manager: CalendarManager(service: ObjectBoxCalendarStorage(store: store))))
        await loadedModel.fetch(force: true)
        model = loadedModel
    }
    
    private func someDate(daysFromNow: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date()) ?? Date()
    }
}
