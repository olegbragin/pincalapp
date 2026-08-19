import SwiftUI

struct PCCard<Content: View>: View {
    var cornerRadius: CGFloat = 16
    private let content: Content

    init(cornerRadius: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .pcGlass(cornerRadius: cornerRadius)
    }
}
