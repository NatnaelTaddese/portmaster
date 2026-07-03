import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = IslandState()
    private let scanner = PortScanner()
    private var windowController: NotchWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = NotchWindowController(state: state, scanner: scanner)
        windowController = controller
        positionWindow()

        // Keep the island's height + collapsed badge in sync with the scan.
        scanner.$ports
            .map(\.count)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.state.portCount = $0 }
            .store(in: &cancellables)

        // Scan faster while the island is open.
        state.$isExpanded
            .removeDuplicates()
            .sink { [weak self] in self?.scanner.setActive($0) }
            .store(in: &cancellables)

        // Follow display changes (lid open/close, external monitors).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.positionWindow() }

        // A click anywhere outside the island collapses it, even when pinned.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.state.isExpanded else { return }
            self.state.collapse()
        }

        scanner.start()

        if ProcessInfo.processInfo.environment["PORTMASTER_START_EXPANDED"] == "1" {
            state.isPinned = true
            state.isExpanded = true
        }
    }

    private func positionWindow() {
        guard let screen = NotchWindowController.targetScreen(),
              let controller = windowController else { return }
        state.updateScreenMetrics(for: screen)
        controller.layout(on: screen)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    }
}
