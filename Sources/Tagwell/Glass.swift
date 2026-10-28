import SwiftUI

// Liquid Glass on macOS 26 and later. macOS 15 keeps the look it had: the standard controls
// already turn to glass on their own, these cover the places Tagwell styles itself.
extension View {
    /// A glass button, or tinted glass for the main action. On macOS 15 the button keeps `fallback`.
    @ViewBuilder
    func glassButtonStyle<Fallback: PrimitiveButtonStyle>(
        prominent: Bool = false,
        otherwise fallback: Fallback = DefaultButtonStyle()
    ) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            buttonStyle(fallback)
        }
    }

    /// A small label floating on a picture: a dark glass capsule, or a dark plate on macOS 15.
    @ViewBuilder
    func glassBadge() -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.tint(.black.opacity(0.35)), in: .capsule)
        } else {
            background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
        }
    }
}
