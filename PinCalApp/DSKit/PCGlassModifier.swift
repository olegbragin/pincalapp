import SwiftUI

struct PCGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?

    func body(content: Content) -> some View {
        #if targetEnvironment(simulator)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(tint ?? .clear))
                    .overlay(shape.stroke(Color.black.opacity(0.2), lineWidth: 1))
            )
        #else
        if #available(iOS 26.0, macOS 26.0, visionOS 27.0, *) {
            content
                .glassEffect(
                    tint.map { Glass.regular.tint($0) } ?? .regular,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(tint ?? .clear)
                        )
                )
        }
        #endif
    }
}

extension View {
    func pcGlass(cornerRadius: CGFloat = 12, tint: Color? = nil) -> some View {
        modifier(PCGlassModifier(cornerRadius: cornerRadius, tint: tint))
    }
}
