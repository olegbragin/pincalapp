//
//  CalendarListView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 09.02.2026.
//

import SwiftUI

struct CalendarListView: View {
    @Binding var selector: RootSelectionCoordinator
    @State private var viewModel = CalendarListViewModel()
    
    @Environment(\.editMode) private var editMode
    
    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selector.selectedItem) {
            ForEach(viewModel.calendars.indices, id: \.self) { index in
                DSCard {
                    VStack {
                        HStack {
                            Image(systemName: "calendar")
                            if viewModel.isEditing {
                                DSTextField(title: "Введите название календаря", text: $viewModel.calendars[index].name)
                            } else {
                                Text(viewModel.calendars[index].name)
                            }
                        }
                        Text("Number of columns: \(viewModel.calendars[index].numberOfColumns)")
                    }
                    .padding()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .tag(
                    RootSelection.calendar(id: viewModel.calendars[index].id)
                )
            }
            .onDelete(perform: deleteItems)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                USEditButton(isEditing: $viewModel.isEditing) { isEditing in
                    if isEditing {
                        viewModel.save()
                    } else {
                        viewModel.isEditing.toggle()
                    }
                }
                if viewModel.isEditing {
                    Button("Save", systemImage: "checkmark") {
                        viewModel.save()
                    }
                }
            }
            ToolbarItem {
                Button(action: viewModel.addItem) {
                    Label("Add Item", systemImage: "plus")
                }
            }
        }
        .task {
            try? await viewModel.fetch()
        }
        .refreshable {
            try? await viewModel.fetch()
        }
        .onChange(of: viewModel.addEditCalendarViewModel.calendar) {
            if $0 != $1, let calendar = $1 {
                viewModel.addCalendar(with: calendar.name)
            }
        }
        .onChange(of: viewModel.isEditing) {
            if $0 != $1 {
                editMode?.wrappedValue = $1 ? .active : .inactive
            }
        }
        .sheet(isPresented: $viewModel.isAddEditSheetPresented) {
            AddEditCalendarView(viewModel: viewModel.addEditCalendarViewModel)
        }
            
            Text(appVersion)
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                viewModel.removeCalendar(viewModel.calendars[index])
            }
        }
    }
}
