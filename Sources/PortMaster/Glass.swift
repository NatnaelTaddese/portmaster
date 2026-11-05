import SwiftUI

// Liquid Glass styling: glass surfaces with hairline, light-catching borders
// and bordered inset panes. Everything is gated on macOS 26; older systems
// keep the flat palette look.

/// Hairline border for glass surfaces: brighter along the top edge, fading
/// toward the bottom, so the edge reads as catching light rather than a flat
/// outline.
struct GlassBorder<S: InsettableShape>: View {
    let shape: S
    var opacity: Double = 1
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let top: Color = colorScheme == .dark ? .white.opacity(0.28) : .white.opacity(0.85)
        let bottom: Color = colorScheme == .dark ? .white.opacity(0.06) : .black.opacity(0.10)
        shape.strokeBorder(
            LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom),
            lineWidth: 1 / displayScale
        )
        .opacity(opacity)
        .allowsHitTesting(false)
    }
}

extension View {
    /// Fills `shape` with Liquid Glass on macOS 26 (falling back to `fallback`
    /// elsewhere) and draws a hairline light-catching border on top.
    @ViewBuilder
    func glassSurface<S: InsettableShape>(
        in shape: S,
        fallback: Color,
        enabled: Bool = true
    ) -> some View {
        if #available(macOS 26, *), enabled {
            self
                .glassEffect(.regular, in: shape)
                .overlay(GlassBorder(shape: shape))
        } else {
            self.background(shape.fill(fallback))
        }
    }

    /// A bordered inset pane, like a split pane in a terminal: a faint fill and
    /// a hairline border around a block of rows.
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
            .overlay(
                shape.strokeBorder(palette.paneBorder, lineWidth: 1 / displayScale)
                    .allowsHitTesting(false)
            )
    }
}
