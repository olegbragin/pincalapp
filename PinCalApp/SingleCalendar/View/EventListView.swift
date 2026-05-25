//
//  EventListView.swift
//  USkateAppV2
//
//  Created by Oleg Bragin on 13.03.2026.
//

import SwiftUI

struct EventListView: View {
    @Bindable var viewModel: EventListViewModel
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editMode) private var editMode
    
    var body: some View {
        NavigationStack {
            VStack {
                List {
                    ForEach(viewModel.events, id: \.self) { event in
                        Button(
                            action: {
                                viewModel.prepareAddEditViewModel(with: event)
                            },
                            label: {
                                HStack {
                                    Text(event.name)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .frame(minWidth: 0, maxWidth: .infinity)
                            }
                        )
                        .listRowBackground(Color(event.color))
                    }
                    .onDelete(perform: deleteItems)
                }
                .environment(\.editMode, editMode)
                .animation(.easeInOut(duration: 0.3), value: viewModel.isEditing)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    USEditButton(isEditing: $viewModel.isEditing) { isEditing in
                        if isEditing {
                            viewModel.commitDelete()
                        } else {
                            viewModel.isEditing.toggle()
                        }
                    }
                }
                ToolbarItem(placement: .title) {
                    Text(viewModel.selectedDay ?? Date(), style: .date)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    USEditButton(
                        isEditing: $viewModel.isEditing,
                        action: { isEditing in
                            if isEditing {
                                viewModel.cancel()
                            } else {
                                viewModel.prepareAddEditViewModel(with: .init(name: "", date: viewModel.selectedDay ?? .now, color: "", timestamp: UUID()))
                            }
                        },
                        activeContent: {
                            AnyView(Text("Cancel"))
                        },
                        inactiveContent: {
                            AnyView(Image(systemName: "plus"))
                        }
                    )
                }
            }
            .navigationDestination(isPresented: $viewModel.addEditEventModel.isPresented) {
                AddEditEventView(viewModel: viewModel.addEditEventModel)
            }
        }
        .onChange(of: viewModel.addEditEventModel.isPresented) {
            if $0 != $1, !$1 {
                viewModel.addEditEventModel.reset()
                viewModel.cancel()
            }
        }
        .onChange(of: viewModel.addEditEventModel.event) {
            if $0 != $1, let eventToCommit = $1 {
                viewModel.apply(with: eventToCommit)
            }
        }
        .onChange(of: viewModel.isEditing) {
            if $0 != $1 {
                editMode?.wrappedValue = $1 ? .active : .inactive
            }
        }
    }

    private func deleteItems(offsets: IndexSet) {
        viewModel.removeEvents(at: offsets)
    }
}
