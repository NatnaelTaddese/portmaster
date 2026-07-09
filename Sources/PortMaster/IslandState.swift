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
    let rowHeight: CGFloat = 40          // one port (same in or out of a group)
    let groupCardPadding: CGFloat = 14   // container inset + gap around a multi-port group
    let sectionHeaderHeight: CGFloat = 24
    let footerHeight: CGFloat = 28
    let maxVisibleRows = 8

    /// Number of "Dev servers" / "System" section headers currently shown (0–2).
    @Published var visibleSectionCount = 0

    /// Measured pixel height of the grouped list body, kept in sync with each
    /// scan (see AppDelegate). Drives `listHeight`.
    @Published var contentHeight: CGFloat = 0

    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?

    var listHeight: CGFloat {
        guard portCount > 0 else { return 108 }
        // Cap at ~8 plain rows' worth of height, then the list scrolls.
        let cap = CGFloat(maxVisibleRows) * rowHeight
        let measured = contentHeight > 0
            ? contentHeight
            : CGFloat(min(portCount, maxVisibleRows)) * rowHeight
        return min(measured, cap)
    }

    /// Measures the grouped list body: each section header, plus every port as a
    /// full row, with a little extra for the container around multi-port groups.
    func measuredContentHeight(devGroups: [[ListeningPort]],
                               systemGroups: [[ListeningPort]]) -> CGFloat {
        func height(_ groups: [[ListeningPort]]) -> CGFloat {
            groups.reduce(0) { total, group in
                total + CGFloat(group.count) * rowHeight
                    + (group.count > 1 ? groupCardPadding : 0)
            }
        }
        var total: CGFloat = 0
        if !devGroups.isEmpty { total += sectionHeaderHeight + height(devGroups) }
        if !systemGroups.isEmpty { total += sectionHeaderHeight + height(systemGroups) }
        return total
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
