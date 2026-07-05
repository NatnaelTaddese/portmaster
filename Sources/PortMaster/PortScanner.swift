import AppKit
import Combine

struct ListeningPort: Identifiable, Equatable {
    let port: Int
    let pid: Int32
    let command: String
    let addresses: [String]
    var repoName: String? = nil      // git root directory name, when the process runs in a repo
    var gitBranch: String? = nil     // current branch of that repo

    var id: String { "\(pid):\(port)" }

    /// The app/command name (independent of any repo it runs in).
    var processName: String {
        if let app = NSRunningApplication(processIdentifier: pid_t(pid)),
           let name = app.localizedName, !name.isEmpty {
            return name
        }
        return command
    }

    /// Repo name when the process lives in a git repo, else the app/command name.
    var displayName: String {
        if let repoName, !repoName.isEmpty { return repoName }
        return processName
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

    // Git resolution caches — only ever touched on `queue`, so no locking needed.
    private var gitRootCache: [String: URL?] = [:]                    // cwd -> git root (nil = not a repo)
    private var branchCache: [String: (branch: String, at: Date)] = [:]  // rootPath -> branch + fetch time
    private static let branchTTL: TimeInterval = 30

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
            guard let self else { return }
            var result = Self.runLsof()
            let usage = Self.runPs(pids: Set(result.map(\.pid)))
            result = self.enrichWithGit(result)
            DispatchQueue.main.async {
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

    // MARK: - Git

    /// Fills in `repoName`/`gitBranch` for any port whose process runs inside a git repo.
    /// Runs on `queue`; safe to touch the caches here.
    private func enrichWithGit(_ ports: [ListeningPort]) -> [ListeningPort] {
        guard !ports.isEmpty else { return ports }

        let cwds = Self.resolveCWDs(pids: Set(ports.map(\.pid)))

        // Resolve a git root per distinct cwd (cached indefinitely — a dir's repo
        // membership doesn't change), then a branch per distinct root (cached ~30s).
        var rootForCWD: [String: URL] = [:]
        var branchForRoot: [String: String] = [:]

        for cwd in Set(cwds.values) {
            let root: URL?
            if let cached = gitRootCache[cwd] {
                root = cached
            } else {
                root = Self.findGitRoot(from: cwd)
                gitRootCache[cwd] = root
            }
            guard let root else { continue }
            rootForCWD[cwd] = root

            let rootPath = root.path
            if branchForRoot[rootPath] != nil { continue }
            if let entry = branchCache[rootPath],
               Date().timeIntervalSince(entry.at) < Self.branchTTL {
                branchForRoot[rootPath] = entry.branch
            } else if let branch = Self.gitBranch(at: rootPath) {
                branchForRoot[rootPath] = branch
                branchCache[rootPath] = (branch, Date())
            }
        }

        // Prune caches for cwds/roots that are no longer live.
        let liveCWDs = Set(cwds.values)
        gitRootCache = gitRootCache.filter { liveCWDs.contains($0.key) }
        let liveRoots = Set(rootForCWD.values.map(\.path))
        branchCache = branchCache.filter { liveRoots.contains($0.key) }

        return ports.map { port in
            guard let cwd = cwds[port.pid], let root = rootForCWD[cwd] else { return port }
            var enriched = port
            enriched.repoName = root.lastPathComponent
            enriched.gitBranch = branchForRoot[root.path]
            return enriched
        }
    }

    /// Maps pids to their current working directory via `lsof -a -p <pids> -d cwd -Fn`.
    private static func resolveCWDs(pids: Set<Int32>) -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-p", pids.map(String.init).joined(separator: ","), "-d", "cwd", "-Fn"]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do { try process.run() } catch { return [:] }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [:] }

        var result: [Int32: String] = [:]
        var currentPID: Int32?
        for line in text.split(separator: "\n") {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())
            switch field {
            case "p":
                currentPID = Int32(value)
            case "n":
                if let pid = currentPID, value.hasPrefix("/") { result[pid] = value }
            default:
                break
            }
        }
        return result
    }

    /// Walks up from `path` looking for a `.git` entry. No shell invocation.
    private static func findGitRoot(from path: String) -> URL? {
        var current = URL(fileURLWithPath: path)
        let fm = FileManager.default
        while current.path != "/" {
            if fm.fileExists(atPath: current.appendingPathComponent(".git").path) {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    /// Current branch via `git -C <root> rev-parse --abbrev-ref HEAD`.
    /// Returns nil on failure or detached HEAD.
    private static func gitBranch(at rootPath: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", rootPath, "rev-parse", "--abbrev-ref", "HEAD"]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do { try process.run() } catch { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else { return nil }
        let branch = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (branch.isEmpty || branch == "HEAD") ? nil : branch
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
