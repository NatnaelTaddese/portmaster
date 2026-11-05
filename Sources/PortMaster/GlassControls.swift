import SwiftUI

// Liquid Glass for small floating controls only (header buttons, kill
// buttons, the copied toast), the way Rex uses it on its toolbar and tab
// pills. Surfaces stay solid so the list's colors never pick up a tint from
// whatever is behind the window. On macOS < 26 these fall back to the flat
// palette fills.

extension View {
    /// Backs the view with a glass `shape` on macOS 26, optionally tinted, or
    /// with a flat `fallback` fill on older systems.
    @ViewBuilder
    func glassChip<S: Shape>(
        _ shape: S,
        fallback: Color,
        tint: Color? = nil,
        interactive: Bool = true
    ) -> some View {
        if #available(macOS 26, *) {
            glassEffect(makeGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            background(shape.fill(fallback))
        }
    }
}

@available(macOS 26, *)
private func makeGlass(tint: Color?, interactive: Bool) -> Glass {
    var glass = Glass.regular
    if let tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return glass
}
