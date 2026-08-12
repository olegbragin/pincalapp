import SwiftUI

struct DSProgressView: View {
    var label: String? = nil

    var body: some View {
        Group {
            if let label {
                ProgressView { Text(label) }
            } else {
                ProgressView()
            }
        }
    }
}
