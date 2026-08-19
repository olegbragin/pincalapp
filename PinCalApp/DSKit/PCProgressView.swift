import SwiftUI

struct PCProgressView: View {
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
