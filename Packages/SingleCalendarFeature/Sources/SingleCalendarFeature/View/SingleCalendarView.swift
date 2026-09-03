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
                        navigation.goTo(route)
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
            .toolbarBackground(Color.dsKit.colorBackgroundMain, for: .navigationBar)
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
                case .calendar:
                    EmptyView() // Not pushed, handled by split view
                case .addCalendar:
                    EmptyView() // Not pushed, presented as sheet
                case .sidebar:
                    EmptyView() // Not pushed, handled by split view sidebar
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
