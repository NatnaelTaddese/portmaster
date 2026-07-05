import AppKit
import Combine

/// Where PortMaster presents itself: over the notch, or as a menu bar extra.
enum AppMode: String {
    case notch
    case menuBar
}

private let displayModeKey = "displayMode"

/// Drives the island's geometry and expand/collapse behavior.
final class IslandState: ObservableObject {
    @Published var isExpanded = false
    @Published var isPinned = false
    @Published var portCount = 0

    /// Selected presentation surface, persisted across launches.
    @Published var mode: AppMode =
        AppMode(rawValue: UserDefaults.standard.string(forKey: displayModeKey) ?? "") ?? .notch {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: displayModeKey) }
    }

    @Published var notchWidth: CGFloat = 200
    @Published var notchHeight: CGFloat = 32
    @Published var hasNotch = false

    // Window is always this size; the island renders top-centered inside it.
    static let windowSize = CGSize(width: 640, height: 560)

    /// Points the black surface bleeds above the physical top edge of the
    /// screen. Guarantees the opaque fill (and the top stroke line) overshoot
    /// the edge so no desktop hairline shows between the screen and the island.
    static let topOverscan: CGFloat = 3

    let expandedWidth: CGFloat = 520
    let headerHeight: CGFloat = 46
    let rowHeight: CGFloat = 40
    let footerHeight: CGFloat = 28
    let maxVisibleRows = 8

    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?

    var listHeight: CGFloat {
        portCount == 0 ? 108 : CGFloat(min(portCount, maxVisibleRows)) * rowHeight
    }

    var expandedHeight: CGFloat {
        notchHeight + headerHeight + listHeight + footerHeight
    }

    /// Collapsed, the island hides behind the physical notch with a 2pt lip.
    /// Without a notch (external display) it shows as a small pill instead.
    var collapsedSize: CGSize {
        hasNotch
            ? CGSize(width: notchWidth, height: notchHeight + 2)
            : CGSize(width: max(120, notchWidth * 0.7), height: notchHeight)
    }

    var currentIslandSize: CGSize {
        isExpanded
            ? CGSize(width: max(expandedWidth, notchWidth + 40), height: expandedHeight)
            : collapsedSize
    }

    func updateScreenMetrics(for screen: NSScreen) {
        if screen.safeAreaInsets.top > 0 {
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            hasNotch = true
            notchWidth = max(120, screen.frame.width - left - right)
            notchHeight = screen.safeAreaInsets.top
        } else {
            hasNotch = false
            notchWidth = 190
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            notchHeight = menuBar > 0 && menuBar < 50 ? menuBar : 24
        }
    }

    // MARK: - Hover choreography

    func hoverChanged(inside: Bool) {
        if inside {
            collapseWork?.cancel()
            guard !isExpanded else { return }
            let work = DispatchWorkItem { [weak self] in self?.isExpanded = true }
            expandWork?.cancel()
            expandWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        } else {
            expandWork?.cancel()
            guard isExpanded, !isPinned else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.isPinned else { return }
                self.isExpanded = false
            }
            collapseWork?.cancel()
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }

    func toggleMode() {
        mode = (mode == .notch) ? .menuBar : .notch
    }

    func toggleExpanded() {
        collapseWork?.cancel()
        expandWork?.cancel()
        isExpanded.toggle()
        if !isExpanded { isPinned = false }
    }

    func collapse() {
        collapseWork?.cancel()
        expandWork?.cancel()
        isPinned = false
        isExpanded = false
    }
}
