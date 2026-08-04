//
//  SingleCalendarView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 04.02.2026.
//

import SwiftUI

struct SingleCalendarView: View {
    @Bindable var viewModel: SingleCalendarModel
        
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            switch viewModel.state {
            case .empty:
                EmptyView()
            case .loading:
                ProgressView {
                    Text("Loading")
                }
            case .content:
                VStack {
                    if viewModel.daySelectionManager.selectionMode == .multiple {
                        ColorPickerView(selectedColor: $viewModel.selectedColor)
                            .disabled(viewModel.isColorPickerDisabled)
                    }
                    USCalendarYearView(
                        viewModel: viewModel.yearModel
                    )
                }
                .sheet(isPresented: $viewModel.isEditSheetPresented) {
                    if viewModel.daySelectionManager.selectionMode == .single {
                        AddEditEventBatchListView(viewModel: viewModel.addEditBatchListViewModel)
                    } else {
                        NavigationStack {
                            AddEditEventBatchView(viewModel: viewModel.addEditBatchListViewModel.addEditEventBatchModel)
                        }
                    }
                }
                .onChange(of: viewModel.yearModel.numberOfColumns) {
                    if $0 != $1 {
                        viewModel.save(for: viewModel.calendarid)
                    }
                }
                .onChange(of: viewModel.daySelectionManager.selectedDays) { _, newValue in
                    if viewModel.daySelectionManager.selectionMode == .multiple, let selectedDay = newValue.first {
                        if let selectedColor = viewModel.selectedColor {
                            viewModel.changeEvent(.init(name: "Event1", date: selectedDay, color: selectedColor.colorName))
                        }
                    } else if !newValue.isEmpty {
                        viewModel.prepareAddEditBatchListViewModel(with: newValue)
                    }
                }
                .onChange(of: viewModel.isEditSheetPresented) { oldValue, newValue in
                    if oldValue != newValue, !newValue {
                        viewModel.resetSelectedDays()
                    }
                }
                .onChange(of: viewModel.addEditBatchListViewModel.eventBatchesToChange) {
                    if $0 != $1 {
                        viewModel.apply(batches: $1, action: .change, for: viewModel.calendarid)
                    }
                }
                .onChange(of: viewModel.addEditBatchListViewModel.eventBatchesToDelete) {
                    if $0 != $1 {
                        viewModel.apply(batches: $1, action: .delete, for: viewModel.calendarid)
                    }
                }
//                Button(
//                    action: {
//                        print("ergaerrg")
//                    },
//                    label: {
//                        Image(systemName: "plus")
//                            .padding(16)
//                    }
//                )
//                .foregroundStyle(.white)
//                .buttonStyle(.glassProminent)
//                .frame(width: 48, height: 48)
//                .clipShape(RoundedRectangle(cornerRadius: 24))
//                .padding(.bottom, 20)
//                .padding(.trailing, 20)
            }
        }
        .ignoresSafeArea()
        .padding(6)
        .navigationTitle(viewModel.label)
        .toolbar {
            ToolbarItem {
                Button(
                    viewModel.daySelectionManager.selectionMode == .multiple ? "Save" : "Multiselect",
                    systemImage: viewModel.daySelectionManager.selectionMode == .multiple ? "checkmark" : "plus.rectangle.on.rectangle"
                ) {
                    if viewModel.daySelectionManager.selectionMode == .multiple {
                        viewModel.prepareAddEditEventBatchViewModel()
                    } else {
                        viewModel.daySelectionManager.toggleSelectionMode()
                    }
                }
            }
            ToolbarItem {
                if viewModel.daySelectionManager.selectionMode == .multiple {
                    Button("Cancel") {
                        viewModel.cancelMultipleChanges()
                    }
                }
            }
        }
        .task(id: viewModel.calendarid) {
            await viewModel.fetch()
        }
        .id(viewModel.calendarid)
    }
}
