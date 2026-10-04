
import SwiftUI

public struct PCButton<Label: View>: View {
    private let action: () -> Void
    private let label: Label
    private let identifier: String?

    public init(
        action: @escaping () -> Void,
        identifier: String? = nil,
        @ViewBuilder label: () -> Label
    ) {
        self.action = action
        self.identifier = identifier
        self.label = label()
    }

    public var body: some View {
        // The identifier goes on the **`Button`** — not on this wrapper, and not on the label.
        //
        // Applied to the wrapper it is accepted and then quietly lost: the wrapper is a
        // `View` whose body *is* the `Button`, and a caller cannot reach past it to put
        // anything on the `Button` itself. That is why `add-calendar-save-button` matched
        // nothing while `add-calendar-sheet` and `add-calendar-name-field` — both plain
        // views in the same sheet — were both findable. The two that are plain views worked;
        // the one that was a `PCButton` did not.
        //
        // On the label's `Text` it does not work either: a `Button` absorbs its label's text
        // as the button's own label rather than exposing it separately, so an identifier
        // there has nothing to attach to. Both were tried; both matched nothing.
        if let identifier {
            base.accessibilityIdentifier(identifier)
        } else {
            base
        }
    }

    /// Deliberately *no* identifier by default. An empty string would be a real, matchable
    /// value, so every unnamed button would answer to the same query — worse than none.
    private var base: some View {
        Button(action: action) {
            label
                .fontWeight(.medium)
        }
    }
}
