//
//  AddEditListView.swift
//  PinCalApp
//
//  Created by Oleg Bragin on 07.07.2026.
//

import SwiftUI
import DSKit
import CorePersistence
import AppNavigation

public struct AddEditListView: View {
    @Bindable public var viewModel: AddEditListViewModel
    @Environment(RootNavigation.self) private var navigation

    public init(viewModel: AddEditListViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        List {
            ForEach(viewModel.events, id: \.self) { event in
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
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AddEditListView(viewModel: .init(events: [.init(name: "1", date: Date(), color: "eventColorOption1")]))
}
