import SwiftUI

/// Fades a scroll view's content out at the top and bottom edges, but only
/// where there is more content past that edge. Each fade grows in over the
/// first `length` points of scroll, so at rest the first and last rows are
/// fully opaque. Needs macOS 15's scroll geometry; older systems get no fade.
struct DynamicScrollFade: ViewModifier {
    var length: CGFloat = 28

    /// 0 = no fade at that edge, 1 = full fade.
    private struct Fades: Equatable {
        var top: CGFloat = 0
        var bottom: CGFloat = 0
    }

    @State private var fades = Fades()

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content
                .onScrollGeometryChange(for: Fades.self) { geometry in
                    let hiddenAbove = geometry.visibleRect.minY
                    let hiddenBelow = geometry.contentSize.height - geometry.visibleRect.maxY
                    return Fades(
                        top: min(max(hiddenAbove / length, 0), 1),
                        bottom: min(max(hiddenBelow / length, 0), 1)
                    )
                } action: { _, new in
                    fades = new
                }
                .mask(mask)
        } else {
            content
        }
    }

    private var mask: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(1 - fades.top), .black],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: length)
            Rectangle().fill(.black)
            LinearGradient(
                colors: [.black, .black.opacity(1 - fades.bottom)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: length)
        }
    }
}

extension View {
    func dynamicScrollFade(length: CGFloat = 28) -> some View {
        modifier(DynamicScrollFade(length: length))
    }
}
