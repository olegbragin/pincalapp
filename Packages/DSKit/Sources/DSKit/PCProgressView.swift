import SwiftUI

public struct PCProgressView: View {
    public var label: String? = nil

    public init(label: String? = nil) {
        self.label = label
    }

    public var body: some View {
        Group {
            if let label {
                ProgressView { Text(label) }
            } else {
                ProgressView()
            }
        }
    }
}