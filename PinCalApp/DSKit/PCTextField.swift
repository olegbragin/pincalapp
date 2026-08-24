import SwiftUI

struct PCTextField: View {
    let title: String
    @Binding var text: String
    var identifier: String? = nil

    var body: some View {
        TextField(title, text: $text)
            .textFieldStyle(.roundedBorder)
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
