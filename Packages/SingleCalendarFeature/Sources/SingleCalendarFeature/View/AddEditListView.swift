//
//  AddEditListView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 07.07.2026.
//

import SwiftUI
import DSKit
import AppNavigation

public struct AddEditListView: View {
    @State private var viewModel: AddEditListViewModel
    @Environment(RootNavigation.self) private var navigation

    public init(manager: PCEventsSelectionManager) {
        _viewModel = State(initialValue: AddEditListViewModel(eventsSelectionManager: manager))
    }
    
    public var body: some View {
        List {
            ForEach(viewModel.events, id: \.self) { event in
                HStack(spacing: 12) {
                    PCCard {
                        Button(
                            action: {
                                navigation.goTo(.eventEditor(EventEditorSource(
                                    id: event.id,
                                    name: event.name,
                                    date: event.date,
                                    color: event.color,
                                    timestamp: event.timestamp
                                )))
                            },
                            label: {
                                HStack(spacing: 12) {
                                    Text(.eventAt(event.name, event.date.formatted(date: .omitted, time: .shortened)))
                                        .foregroundStyle(Color.dsKit.colorForegroundOnEventCard)
                                    
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .frame(minWidth: 0, maxWidth: .infinity)
                            }
                        )
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.dsKit.eventColor(named: event.color))
                        )
                    }

                    Button {
                        viewModel.remove(event)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete event")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AddEditListView(manager: .init(events: [.init(name: "1", date: Date(), color: "eventColorOption1")]))
}
