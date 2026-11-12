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

    /// A bar that floats over the window's content: glass, or the regular material on macOS 15.
    /// Only for the layer of controls and messages, never for rows or pictures.
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = 12) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
