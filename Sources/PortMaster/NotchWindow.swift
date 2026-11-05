import AppKit
import Combine
import SwiftUI

/// Non-activating borderless panel that floats over the notch on every space,
/// including over full-screen apps.
final class NotchPanel: NSPanel {
    weak var islandState: IslandState?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        // Must come after isFloatingPanel — its setter resets level to .floating.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Allow the panel to sit over the menu bar / notch area unclamped.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func cancelOperation(_ sender: Any?) {
        islandState?.collapse()
    }
}

/// Container that only accepts mouse events over the island itself, so the
/// rest of the (invisible) window never blocks menu bar or desktop clicks.
final class IslandHitTestView: NSView {
    var islandState: IslandState?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let state = islandState else { return nil }
        let local = convert(point, from: superview)
        let size = state.currentIslandSize
        let island = CGRect(
            x: (bounds.width - size.width) / 2,
            y: 0,
            width: size.width,
            // Include the overscan lift so the bottom lip stays interactive.
            height: size.height + IslandState.topOverscan
        ).insetBy(dx: -6, dy: 0)
        guard island.contains(local) else { return nil }
        return super.hitTest(point)
    }
}

final class NotchWindowController {
    let panel: NotchPanel
    private let container = IslandHitTestView()
    private var cancellables = Set<AnyCancellable>()

    init(state: IslandState, scanner: PortScanner, openSettings: @escaping () -> Void) {
        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: IslandState.windowSize))
        panel.islandState = state
        container.islandState = state

        // The panel's appearance drives SwiftUI's colorScheme (and the scroller,
        // spinner and context menu). Over a physical notch the island is always
        // black, so pin it to dark there regardless of the user's choice.
        Publishers.CombineLatest(state.$appearance, state.$hasNotch)
            .map { appearance, hasNotch -> NSAppearance? in
                hasNotch ? NSAppearance(named: .darkAqua) : appearance.nsAppearance
            }
            .removeDuplicates { $0?.name == $1?.name }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.panel.appearance = $0 }
            .store(in: &cancellables)

        let hosting = NSHostingView(
            rootView: IslandRootView(state: state, scanner: scanner, openSettings: openSettings)
        )
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container
    }

    /// Prefer the built-in (notched) display; fall back to the main screen.
    static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    func layout(on screen: NSScreen) {
        let size = IslandState.windowSize
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            // Lift the top edge above the screen so the island's black bleeds
            // past the physical edge instead of leaving a desktop hairline.
            y: screen.frame.maxY - size.height + IslandState.topOverscan,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }
}
