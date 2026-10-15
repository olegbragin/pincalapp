//
//  AddEditEventBatchView.swift
//  SingleCalendarFeature
//
//  Created by Oleg Bragin on 02.07.2026.
//

import SwiftUI
import DSKit

public struct AddEditEventBatchView: View {
    @Environment(PCEventSelectionManager.self) private var store
    @Environment(\.pcVibe) private var vibe

    public init() {}

    public var body: some View {
        let viewModel = AddEditEventBatchViewModel(store: store)

        // A plain `ScrollView` of two `Group`s, and not a `Form`.
        //
        // The `Form` was a fight that was being lost. It owns its own background, its own
        // row insets, its own section spacing and its own scroller, so every one of those had
        // to be overridden to get the app's look — and the overrides were the only thing
        // distinguishing this editor from a Settings screen. What is actually wanted here is
        // spacing and a scroll, both of which a `ScrollView` and a `VStack` already do.
        //
        // Two groups, because the editor is two things: what this batch *is* (name, colour)
        // and which days it *holds*. The time picker is in the second, and that is not
        // tidiness — a time is not a batch attribute, it belongs to the events, and it acts
        // on the *selection* of rows below it. Neither group is titled: a heading only earns
        // its place by saying something the contents do not, and both were saying "this is
        // the batch's name" over a field asking for one.
        ScrollView {
            VStack(spacing: 12) {
                Group {
                    HStack(spacing: 12) {
                        PCTextField(title: viewModel.namePlaceholder, text: viewModel.nameBinding, identifier: "batch-name-field")
                            // "As soon as the user finishes entering the name, save everything."
                            // The keystrokes already merged the batch, so this is only about the
                            // debounce: without it a name typed in the last quarter-second is
                            // still sitting on `nameAutosave` when the user puts the phone down,
                            // and nothing has asked for it to be written yet.
                            .onSubmit { store.send(.nameEditingFinished) }

                        PCColorPickerView(
                            selectedColor: viewModel.colorBinding,
                            selectColorLabel: String(localized: .selectColor),
                            optionNames: pcColorOptionNames(),
                            defaultColor: viewModel.defaultColor
                        )
                    }
                }

                Group {
                    PCEventTimePicker(
                        displayedTime: viewModel.displayedEventTime,
                        isEnabled: viewModel.isTimePickerEnabled,
                        // Words come from here, not from DSKit: the package does not choose its
                        // own copy, and `DSKitTests` fails it if it tries.
                        title: String(localized: "Select time"),
                        cancelTitle: String(localized: "Cancel"),
                        doneTitle: String(localized: "Done"),
                        accessibilityName: String(localized: "Event time"),
                        onCommit: { viewModel.applyTime($0) }
                    )

                    AddEditEventListView()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(8)
        }
        // The panel is drawn on the **`ScrollView`**, not on its content.
        //
        // Two failed attempts are recorded here so the next one does not repeat them. A
        // scroll view is sized by its content, so `.frame(maxHeight: .infinity)` on it asks
        // its own parent for more and changes nothing. Moving that frame onto the content is
        // no better: a scroll view proposes an *unspecified* height to what is inside it —
        // that is what lets a long batch scroll — so `maxHeight: .infinity` there resolves
        // straight back to the content's own height and the panel still hugged the rows.
        //
        // Only the scroll view is offered the viewport, so only it can fill it.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The fill is the app's background at half strength rather than a solid one: the
        // calendar sits directly behind this sheet on iPad, and an opaque panel would hide
        // the day markers the user is editing against. The hairline is the other half of
        // that trade — enough edge to read as a surface, not enough to read as a card.
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(vibe.color(for: .background).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.black.opacity(0.1), lineWidth: 0.5)
        )
        .background(vibe.color(for: .backgroundMain))
        .keyboardAvoidable()
        .toolbarTitleDisplayMode(.inline)
        // No Save, and no toolbar of its own.
        //
        // Every field here writes through as it is edited — `setBatchName` is debounced,
        // `setBatchColor` and `toggleDay` are not — so a checkmark could only re-write a row
        // that was already durable or navigate away from one that was. Worse, it was the
        // *only* exit: `saveTapped` is what cleared `state.assembly` and popped, so removing
        // the button without moving that would have left the editor with no way out. Back,
        // which `AddEditEventBatchScreen` already owns and routes through the store, is now
        // the single exit — and it is the better one, because it does not ask about a save
        // that already happened.
        //
        // Back is also where an emptied batch is deleted. `canSave` is not consulted here
        // at all: it was only ever feeding this button's `isEnabled`.
    }
}

#Preview {
    AddEditEventBatchView()
        .environment(PreviewEventSelectionStore.make())
        .environment(PCKeyboardState())
}
