import SwiftUI

struct DSGlassModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
#if targetEnvironment(simulator)
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.clear)
                    .stroke(Color.black.opacity(0.2), lineWidth: 1)
            )
#else
        if #available(iOS 26.0, macOS 26.0, visionOS 27.0, *) {
            content
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
        }
#endif
    }
}

extension View {
    func dsGlass(cornerRadius: CGFloat = 12) -> some View {
        modifier(DSGlassModifier(cornerRadius: cornerRadius))
    }
}
