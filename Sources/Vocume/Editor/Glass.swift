import SwiftUI

extension View {
    /// The one glass layer that floats above the print: Liquid Glass on macOS 26, a regular
    /// material with a hairline edge before that.
    @ViewBuilder
    func floatingGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
    }

    /// A bar that floats over the bottom edge of the content: `safeAreaBar` on macOS 26 (so the
    /// content's scroll edge reacts to it), a plain safe-area inset before that.
    @ViewBuilder
    func floatingBottomBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        if #available(macOS 26, *) {
            safeAreaBar(edge: .bottom, content: bar)
        } else {
            safeAreaInset(edge: .bottom, content: bar)
        }
    }
}
