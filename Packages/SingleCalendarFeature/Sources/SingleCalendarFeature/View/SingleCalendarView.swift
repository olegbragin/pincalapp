//
//  SingleCalendarView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 04.02.2026.
//

import SwiftUI
import CorePersistence
import AppNavigation
import DSKit

public struct SingleCalendarView: View {
    @Bindable public var viewModel: SingleCalendarModel

    public init(viewModel: SingleCalendarModel) {
        self.viewModel = viewModel
    }
    @Environment(RootNavigation.self) var navigation
    
    @State private var columnCountSaveTask: Task<Void, Never>?
        
    public var body: some View {
        ZStack {
            SingleCalendarStateView(state: viewModel.state) {
                AnyView(
                    SingleCalendarCalendarContent(
                        isMultiSelect: viewModel.daySelectionManager.selectionMode == .multiple,
                        selectedColor: $viewModel.selectedColor,
                        isColorPickerDisabled: viewModel.isColorPickerDisabled,
                        yearModel: viewModel.yearModel
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: viewModel.yearModel.numberOfColumns) {
                        if $0 != $1 {
                            scheduleColumnCountSave()
                        }
                    }
                    .onChange(of: viewModel.daySelectionManager.selectedDays) { _, newValue in
                        guard let route = viewModel.route(for: newValue) else { return }
                        navigation.goTo(route)
                    }
                )
            }
            .padding(6)
            .navigationTitle(viewModel.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.dsKit.colorBackgroundMain, for: .navigationBar)
            .toolbar { toolbarContent }
            .id(viewModel.calendarid)
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .dayBatches(let day):
                    AddEditEventBatchListView(
                        eventsSelectionManager: viewModel.eventsSelectionManager,
                        daySelectionManager: viewModel.daySelectionManager,
                        calendarId: viewModel.calendarid,
                        loadBatches: { viewModel.batches(for: day) },
                        selectedDay: day,
                        onDeleteBatches: { viewModel.deleteBatches($0, for: viewModel.calendarid) }
                    )
                case .batchEditor(let source):
                    AddEditEventBatchScreen(
                        eventsSelectionManager: viewModel.eventsSelectionManager,
                        calendarId: viewModel.calendarid,
                        source: source,
                        resolveBatch: { viewModel.batch(withId: $0) },
                        onCommit: { viewModel.commitPendingBatch($0) }
                    )
                case .eventEditor(let source):
                    let selectionManager = viewModel.eventsSelectionManager
                    AddEditEventView(
                        event: EventDataSource(
                            id: source.id,
                            name: source.name,
                            date: source.date,
                            color: source.color,
                            timestamp: source.timestamp
                        ),
                        onCommit: { committed in
                            selectionManager.apply(committed)
                        }
                    )
                case .calendar:
                    EmptyView()
                case .addCalendar:
                    EmptyView()
                case .sidebar:
                    EmptyView()
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .task(id: viewModel.calendarid) {
            await viewModel.fetch()
        }
        .onDisappear {
            flushColumnCountSave()
            // Leaving the calendar detail (back to the list, or switching
            // calendars) must exit any active multiselect session so a later
            // reopen starts fresh. `onChange(of: isAtRoot)` never fires here
            // because the calendar is opened via `detailCalendarID` (not pushed
            // onto the navigation path), so `isAtRoot` stays `true`.
            // Guard on `isAtRoot`: `onDisappear` also fires when a destination
            // (e.g. the batch editor) is pushed on top of the root, and we must
            // not reset the shared session while a batch edit is in progress.
            if navigation.isAtRoot {
                viewModel.resetSelectedDays()
            }
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
                        if let route = viewModel.handleSelectionConfirmation() {
                            navigation.goTo(route)
                        }
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
    var body: some View {
        Text("SingleCalendarView Preview")
    }
}
