//
//  AddEditEventListView.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 07.07.2026.
//

import SwiftUI
import DSKit

/// The events inside the batch being edited.
///
/// Takes no parameters: the list *is* the assembly's events, read from the store.
public struct AddEditEventListView: View {
    @Environment(PCEventSelectionManager.self) private var store
    @Environment(\.pcVibe) private var vibe

    public init() {}

    public var body: some View {
        let viewModel = AddEditEventListViewModel(store: store)

        List {
            ForEach(viewModel.events) { event in
                HStack(spacing: 12) {
                    PCCard {
                        Button {
                            viewModel.open(event)
                        } label: {
                            HStack(spacing: 12) {
                                Text(.eventAt(event.name, event.date.formatted(date: .omitted, time: .shortened)))
                                    .foregroundStyle(vibe.color(for: .foregroundOnEventCard))

                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .frame(minWidth: 0, maxWidth: .infinity)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(vibe.eventColor(named: event.colorName))
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
