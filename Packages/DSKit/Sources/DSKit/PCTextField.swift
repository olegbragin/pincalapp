
import SwiftUI

public struct PCTextField: View {
    let title: String
    @Binding var text: String
    var identifier: String?
    var submitLabel: SubmitLabel = .done

    /// The caller's focus binding, when it wants to know when the field stops being first
    /// responder.
    ///
    /// Optional because not every caller has an opinion. `onSubmit` only fires for the
    /// keyboard's return key, so a field the user *taps away from* — onto a day cell, into
    /// another control, out of a dismissed sheet — reports nothing, and a caller waiting for
    /// "editing finished" waits for a gesture that is not the one they meant.
    ///
    /// Passed in rather than declared here so this stays a dumb field: `@FocusState` is
    /// property-wrapper state and a `View` that owns one cannot be reused across two places in
    /// a tree without them sharing it.
    var focus: FocusState<Bool>.Binding?

    public init(
        title: String,
        text: Binding<String>,
        identifier: String? = nil,
        submitLabel: SubmitLabel = .done,
        focus: FocusState<Bool>.Binding? = nil
    ) {
        self.title = title
        self._text = text
        self.identifier = identifier
        self.submitLabel = submitLabel
        self.focus = focus
    }

    public var body: some View {
        field
            .textFieldStyle(.roundedBorder)
            .tint(.blue)
            .submitLabel(submitLabel)
            .accessibilityIdentifierIfPresent(identifier)
    }

    @ViewBuilder
    private var field: some View {
        if let focus {
            TextField(title, text: $text)
                .focused(focus)
        } else {
            TextField(title, text: $text)
        }
    }
}

extension View {
    @ViewBuilder
    func accessibilityIdentifierIfPresent(_ id: String?) -> some View {
        if let id {
            self.accessibilityIdentifier(id)
        } else {
            self
        }
    }
}
