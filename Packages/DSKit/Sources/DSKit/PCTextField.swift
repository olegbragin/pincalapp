import SwiftUI

public struct PCTextField: View {
    let title: String
    @Binding var text: String
    var identifier: String? = nil
    var submitLabel: SubmitLabel = .done

    public init(title: String, text: Binding<String>, identifier: String? = nil, submitLabel: SubmitLabel = .done) {
        self.title = title
        self._text = text
        self.identifier = identifier
        self.submitLabel = submitLabel
    }

    public var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.roundedBorder)
            .tint(.blue)
            .submitLabel(submitLabel)
            .accessibilityIdentifierIfPresent(identifier)
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