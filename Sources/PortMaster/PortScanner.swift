import AppKit
import Combine

struct ListeningPort: Identifiable, Equatable {
    let port: Int
    let pid: Int32
    let command: String
    let addresses: [String]

    var id: String { "\(pid):\(port)" }

    var displayName: String {
        if let app = NSRunningApplication(processIdentifier: pid_t(pid)),
           let name = app.localizedName, !name.isEmpty {
            return name
        }
        return command
    }

    var addressSummary: String {
        addresses.joined(separator: "  ")
    }
}

struct ProcessUsage: Equatable {
    let cpuPercent: Double
    let memoryBytes: UInt64
}

enum KillState: Equatable {
    case terminating(since: Date)
    case failed(String)

    var isStuck: Bool {
        if case .terminating(let since) = self {
            return Date().timeIntervalSince(since) > 3
        }
        return false
    }
}

final class PortScanner: ObservableObject {
    @Published private(set) var ports: [ListeningPort] = []
    @Published private(set) var killStates: [String: KillState] = [:]
    @Published private(set) var iconCache: [Int32: NSImage] = [:]
    @Published private(set) var usage: [Int32: ProcessUsage] = [:]

    private var timer: Timer?
    private var interval: TimeInterval = 15
    private let queue = DispatchQueue(label: "portmaster.scan", qos: .userInitiated)
    private var isScanning = false

    func start() {
        scanNow()
        reschedule()
    }

    func setActive(_ active: Bool) {
        let newInterval: TimeInterval = active ? 2 : 15
        guard newInterval != interval else { return }
        interval = newInterval
        reschedule()
        if active { scanNow() }
    }

    private func reschedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.scanNow()
        }
        timer?.tolerance = interval * 0.2
    }

    func scanNow() {
        guard !isScanning else { return }
        isScanning = true
        queue.async { [weak self] in
            let result = Self.runLsof()
            let usage = Self.runPs(pids: Set(result.map(\.pid)))
            DispatchQueue.main.async {
                guard let self else { return }
                self.isScanning = false
                self.publish(result, usage: usage)
            }
        }
    }

    private func publish(_ scanned: [ListeningPort], usage newUsage: [Int32: ProcessUsage]) {
        let sorted = scanned.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
        if sorted != ports { ports = sorted }

        // Drop kill bookkeeping for rows that no longer exist.
        let liveIDs = Set(sorted.map(\.id))
        killStates = killStates.filter { liveIDs.contains($0.key) }

        var icons = iconCache
        let livePIDs = Set(sorted.map(\.pid))
        icons = icons.filter { livePIDs.contains($0.key) }
        for pid in livePIDs where icons[pid] == nil {
            if let icon = NSRunningApplication(processIdentifier: pid_t(pid))?.icon {
                icon.size = NSSize(width: 32, height: 32)
                icons[pid] = icon
            }
        }
        if icons != iconCache { iconCache = icons }
        if newUsage != usage { usage = newUsage }
    }

    // MARK: - Killing

    func kill(_ entry: ListeningPort, force: Bool) {
        let sig = force ? SIGKILL : SIGTERM
        if Darwin.kill(pid_t(entry.pid), sig) == 0 {
            killStates[entry.id] = .terminating(since: Date())
        } else {
            let message = errno == EPERM
                ? "No permission (owned by another user)"
                : String(cString: strerror(errno))
            killStates[entry.id] = .failed(message)
        }
        // Re-scan shortly after so the row disappears (or reports back) quickly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.scanNow() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.scanNow() }
    }

    // MARK: - ps

    /// Fetches CPU% and resident memory for the given pids.
    /// `%cpu` is ps's decaying average; `rss` is reported in 1024-byte units.
    private static func runPs(pids: Set<Int32>) -> [Int32: ProcessUsage] {
        guard !pids.isEmpty else { return [:] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = [
            "-o", "pid=,%cpu=,rss=",
            "-p", pids.map(String.init).joined(separator: ","),
        ]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do { try process.run() } catch { return [:] }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [:] }

        var usage: [Int32: ProcessUsage] = [:]
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ")
            guard fields.count >= 3,
                  let pid = Int32(fields[0]),
                  let cpu = Double(fields[1]),
                  let rssKB = UInt64(fields[2]) else { continue }
            usage[pid] = ProcessUsage(cpuPercent: cpu, memoryBytes: rssKB * 1024)
        }
        return usage
    }

    // MARK: - lsof

    /// Parses `lsof +c 0 -iTCP -sTCP:LISTEN -P -n -Fpcn` machine-readable output.
    private static func runLsof() -> [ListeningPort] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["+c", "0", "-iTCP", "-sTCP:LISTEN", "-P", "-n", "-Fpcn"]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do { try process.run() } catch { return [] }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var results: [String: ListeningPort] = [:]
        var pid: Int32 = 0
        var command = "?"

        for line in text.split(separator: "\n") {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())
            switch field {
            case "p":
                pid = Int32(value) ?? 0
            case "c":
                command = value
            case "n":
                guard let colon = value.lastIndex(of: ":"),
                      let port = Int(value[value.index(after: colon)...]) else { continue }
                var address = String(value[..<colon])
                if address == "*" { address = "*" }
                let key = "\(pid):\(port)"
                if let existing = results[key] {
                    if !existing.addresses.contains(address) {
                        results[key] = ListeningPort(
                            port: port, pid: pid, command: command,
                            addresses: existing.addresses + [address]
                        )
                    }
                } else {
                    results[key] = ListeningPort(
                        port: port, pid: pid, command: command, addresses: [address]
                    )
                }
            default:
                break
            }
        }
        return Array(results.values)
    }
}
