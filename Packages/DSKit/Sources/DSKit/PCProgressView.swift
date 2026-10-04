
import SwiftUI

public struct PCProgressView: View {
    public var label: String?

    public init(label: String? = nil) {
        self.label = label
    }

    public var body: some View {
        if let label {
            ProgressView { Text(label) }
        } else {
            ProgressView()
        }
    }
}
