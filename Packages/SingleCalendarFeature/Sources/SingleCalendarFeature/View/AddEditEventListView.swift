//
//  AddEditEventListView.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 07.07.2026.
//

import SwiftUI
import CoreDomain
import DSKit

/// The events inside the batch being edited.
///
/// Takes no parameters: the list *is* the assembly's events, read from the store.
///
/// **Always in edit mode.** Every row carries its checkbox and its delete button from the
/// moment the editor opens, and there is no Select/Done bar to put them there. The bar was a
/// two-state screen in disguise: a row meant "open this event" until Select was tapped and
/// "choose this event" afterwards, so the affordances the user needed — the checkbox, and the
/// count the time picker acts on — were hidden behind a mode they had to know about. With the
/// mode gone, each control does one thing and the meanings stop competing for the same tap.
///
/// Note this is *not* SwiftUI's `\.editMode`, which renders nothing here: it draws reorder
/// handles and swipe-to-delete, and its checkboxes exist only as the red minus on rows that
/// have an `onDelete`. Both would duplicate — and fight — the row's own controls.
public struct AddEditEventListView: View {
    @Environment(PCEventSelectionManager.self) private var store
    @Environment(\.pcVibe) private var vibe

    public init() {}

    public var body: some View {
        let viewModel = AddEditEventListViewModel(store: store)

        // No `ScrollView` here, and no `List` either.
        //
        // This view lives inside the editor's own `ScrollView`, and a scrolling view inside
        // one is a second scroller competing for the same gesture. On iPad that reads as lag:
        // the outer one scrolls, and at the moment it decides the touch is over, the inner
        // one starts moving — so a drag is answered twice and neither scroll tracks the finger.
        // That is not a smoothness problem that a smaller `minHeight` would fix; it is two
        // scrollers.
        //
        // So the rows are laid out and nothing here scrolls. The editor owns the gesture, the
        // rows grow the content, and `LazyVStack` still keeps a long batch from building every
        // card up front.
        LazyVStack(spacing: 12) {
            // `indices` rather than the events alone: the row's accessibility identifier
            // has to be something a UI test can name, and `pendingID` is a fresh `UUID`
            // per session — stable enough for the reducer, useless as a query. The
            // assembly keeps its events sorted by date, so an index names the same day
            // for the whole edit.
            ForEach(Array(viewModel.events.enumerated()), id: \.element.pendingID) { index, event in
                row(index: index, event: event, viewModel: viewModel)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
    }

    private func row(
        index: Int,
        event: CalendarEvent,
        viewModel: AddEditEventListViewModel
    ) -> some View {
        HStack(spacing: 12) {
            // The checkbox, as its own tap target.
            //
            // It has to be separate from the row's own button. The row opens the event —
            // that is still its meaning, and it was the only route to the event editor
            // before — so a checkbox drawn *inside* that label would swallow half the row's
            // target and leave the other half tapping differently from where it looks.
            Button {
                viewModel.toggleSelection(event)
            } label: {
                Image(systemName: viewModel.isSelected(event) ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(viewModel.isSelected(event) ? .deselect : .select))
            .accessibilityIdentifier("batch-event-select-\(index)")

            PCCard {
                Button {
                    viewModel.open(event)
                } label: {
                    HStack(spacing: 12) {
                        Text(String(format: String(localized: .at(event.name, event.date.formatted(date: .omitted, time: .shortened)))))
                            .foregroundStyle(vibe.color(for: .foregroundOnEventCard))

                        Spacer()

                        // The row opens something, and this is the promise of that.
                        Image(systemName: "chevron.right")
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(vibe.eventColor(named: event.colorName))
                )
                // Leaf-level only. The `HStack` around it has a trash button in it, and an
                // identifier on a container shadows everything inside it.
                .accessibilityIdentifier("batch-event-row-\(index)")
            }

            // Deleting and deselecting are different acts, and this is the delete one.
            // The checkbox is the deselect. When selection was a mode, the trash was
            // hidden inside it to avoid offering two ways to destroy a row — but the row
            // has to be deletable in every state it can be in, and in the only state
            // there now is, they are not ambiguous: one is a grey circle that fills, the
            // other is red.
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
            .accessibilityLabel(Text(.deleteEvent))
            .accessibilityIdentifier("batch-event-delete-\(index)")
        }
    }
}
