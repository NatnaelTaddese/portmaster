import SwiftUI

// Terminal-style panes, modeled on Rex: solid neutral surfaces, an even gap
// between panes, and a two-line edge — a 1pt dark outer line plus a hairline
// light inner line — so each pane reads as a slightly bevelled card.

extension View {
    /// A bordered inset pane holding a block of rows.
    func pane(cornerRadius: CGFloat = 12) -> some View {
        modifier(PaneModifier(cornerRadius: cornerRadius))
    }

    /// Hard scroll edge under the header so rows meet the chrome cleanly
    /// instead of fading beneath it (macOS 26 only).
    @ViewBuilder
    func hardScrollEdges() -> some View {
        if #available(macOS 26, *) {
            self.scrollEdgeEffectStyle(.hard, for: .vertical)
        } else {
            self
        }
    }
}

private struct PaneModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.palette) private var palette
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(palette.paneFill))
            .overlay {
                ZStack {
                    shape.strokeBorder(palette.paneEdgeOuter, lineWidth: 1)
                    shape.inset(by: 1)
                        .strokeBorder(palette.paneEdgeInner, lineWidth: 1 / displayScale)
                }
                .allowsHitTesting(false)
            }
    }
}
