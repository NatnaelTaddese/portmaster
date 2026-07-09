import SwiftUI
import AppKit

extension Font {
    /// Bundled Lexend variable font, registered at launch in main.swift.
    static func lexend(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Lexend", size: size).weight(weight)
    }
}

struct IslandRootView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var scanner: PortScanner

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            island
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var cornerRadius: CGFloat { state.isExpanded ? 22 : 9 }

    private var islandShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 0,
                bottomLeading: cornerRadius,
                bottomTrailing: cornerRadius,
                topTrailing: 0
            ),
            style: .continuous
        )
    }

    private var island: some View {
        ZStack(alignment: .top) {
            islandShape.fill(Color.black)

            if state.isExpanded {
                PortListContent(state: state, scanner: scanner)
                    // Extra top padding matches the panel's overscan lift so the
                    // header lands in the same on-screen spot as before.
                    .padding(.top, state.notchHeight + IslandState.topOverscan)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else if !state.hasNotch {
                CollapsedPill(count: state.portCount)
                    .padding(.top, IslandState.topOverscan)
            }
        }
        .frame(
            width: state.currentIslandSize.width,
            // The overscan grows the black fill upward past the screen edge.
            height: state.currentIslandSize.height + IslandState.topOverscan
        )
        .clipShape(islandShape)
        .overlay(
            islandShape.strokeBorder(
                .white.opacity(state.isExpanded ? 0.10 : 0.05),
                lineWidth: 1
            )
        )
        .shadow(
            color: .black.opacity(state.isExpanded ? 0.55 : 0),
            radius: 26, x: 0, y: 12
        )
        .contentShape(Rectangle())
        .onHover { state.hoverChanged(inside: $0) }
        .onTapGesture {
            if !state.isExpanded { state.toggleExpanded() }
        }
        .contextMenu {
            Button("Refresh") { scanner.scanNow() }
            Button("Use Menu Bar Mode") { state.mode = .menuBar }
            Divider()
            Button("Quit PortMaster") { NSApp.terminate(nil) }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.8), value: state.isExpanded)
        .animation(.easeOut(duration: 0.18), value: state.portCount)
    }
}

// MARK: - Collapsed (non-notch displays only)

private struct CollapsedPill: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(count > 0 ? Color.green : Color.gray)
                .frame(width: 5, height: 5)
            Text("\(count)")
                .font(.lexend(11, .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Menu bar popover

/// Hosts the shared port list for the menu bar's `NSPopover`, on its own dark
/// backing at a fixed width (the notch supplies its own black island shape).
struct MenuBarPopoverView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var scanner: PortScanner

    var body: some View {
        PortListContent(state: state, scanner: scanner, showsPin: false)
            .frame(width: state.expandedWidth)
            .background(Color.black)
    }
}

// MARK: - Expanded

/// Header + port list + footer. Shared by the notch island and the menu bar
/// popover; the pin control only makes sense for the (hover-driven) notch.
struct PortListContent: View {
    @ObservedObject var state: IslandState
    @ObservedObject var scanner: PortScanner
    var showsPin: Bool = true
    @State private var hoveredRow: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            if scanner.ports.isEmpty {
                emptyState
            } else {
                portList
            }
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Ports")
                .font(.lexend(12, .semibold))
                .foregroundStyle(.white.opacity(0.6))

            Spacer()

            IconButton(symbol: "arrow.clockwise", help: "Refresh") {
                scanner.scanNow()
            }
            if showsPin {
                IconButton(
                    symbol: state.isPinned ? "pin.fill" : "pin",
                    help: state.isPinned ? "Unpin" : "Keep open",
                    isActive: state.isPinned
                ) {
                    state.isPinned.toggle()
                }
            }
            IconButton(
                symbol: state.mode == .notch ? "menubar.rectangle" : "macwindow",
                help: state.mode == .notch ? "Switch to menu bar" : "Switch to notch"
            ) {
                state.toggleMode()
            }
            IconButton(symbol: "power", help: "Quit PortMaster") {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: state.headerHeight)
    }

    private var devPorts: [ListeningPort]    { scanner.ports.filter { $0.isDevServer } }
    private var systemPorts: [ListeningPort] { scanner.ports.filter { !$0.isDevServer } }

    private var portList: some View {
        ScrollView(.vertical, showsIndicators: scanner.ports.count > state.maxVisibleRows) {
            LazyVStack(spacing: 0) {
                if !devPorts.isEmpty {
                    sectionHeader("Dev servers")
                    ForEach(groupPortsByOwner(devPorts), id: \.first!.id) { groupView($0) }
                }
                if !systemPorts.isEmpty {
                    sectionHeader("System")
                    ForEach(groupPortsByOwner(systemPorts), id: \.first!.id) { groupView($0) }
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: state.listHeight)
    }

    private func row(_ entry: ListeningPort) -> some View {
        PortRow(
            entry: entry,
            icon: scanner.iconCache[entry.pid],
            usage: scanner.usage[entry.pid],
            killState: scanner.killStates[entry.id],
            isHovered: hoveredRow == entry.id,
            rowHeight: state.rowHeight,
            onKill: { force in scanner.kill(entry, force: force) }
        )
        .onHover { hoveredRow = $0 ? entry.id : nil }
    }

    /// One owner group: a plain row when it holds a single port, otherwise an
    /// app header with the ports nested beneath it.
    @ViewBuilder
    private func groupView(_ group: [ListeningPort]) -> some View {
        if group.count == 1 {
            row(group[0])
        } else {
            PortGroupView(
                ports: group,
                icon: scanner.iconCache[group[0].pid],
                usage: scanner.usage,
                killStates: scanner.killStates,
                hoveredRow: hoveredRow,
                groupHeaderHeight: state.groupHeaderHeight,
                subRowHeight: state.subRowHeight,
                onHover: { id, isInside in hoveredRow = isInside ? id : nil },
                onKill: { entry, force in scanner.kill(entry, force: force) }
            )
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.lexend(9.5, .semibold))
                .foregroundStyle(.white.opacity(0.35))
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 3)
        .frame(height: state.sectionHeaderHeight)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.25))
            Text("No listening ports")
                .font(.lexend(12, .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .frame(height: state.listHeight)
    }

    private var footer: some View {
        HStack {
            Text("⌥-click ✕ to force kill")
                .font(.lexend(9.5))
                .foregroundStyle(.white.opacity(0.3))
            Spacer()
            Text("TCP · LISTEN")
                .font(.lexend(9, .medium))
                .foregroundStyle(.white.opacity(0.25))
        }
        .padding(.horizontal, 16)
        .frame(height: state.footerHeight)
    }
}

// MARK: - Row

private struct PortRow: View {
    let entry: ListeningPort
    let icon: NSImage?
    let usage: ProcessUsage?
    let killState: KillState?
    let isHovered: Bool
    let rowHeight: CGFloat
    let onKill: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            portIcon(icon, isContainer: entry.isContainer)
                .frame(width: 20, height: 20)

            Text(verbatim: ":\(entry.port)")
                .font(.lexend(13, .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(entry.displayName)
                        .font(.lexend(12, .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let secondary = fadedLabel(for: entry) {
                        Text(secondary)
                            .font(.lexend(11))
                            .foregroundStyle(.white.opacity(0.35))
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 5) {
                    metaChip(for: entry)
                    Text("\(entry.addressSummary)   pid \(entry.pid)")
                        .font(.lexend(10).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            usageColumn(usage)

            killControl(killState: killState, isHovered: isHovered,
                        port: entry.port, name: entry.displayName, onKill: onKill)
        }
        .padding(.horizontal, 10)
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.white.opacity(isHovered ? 0.07 : 0))
        )
    }

}

// MARK: - Grouped app (multiple ports on one owner)

/// Header row for an app/repo/container that owns several ports, followed by one
/// slim sub-row per port. The icon, name and CPU/mem are shown once; each port
/// keeps its own address, pid and kill button.
private struct PortGroupView: View {
    let ports: [ListeningPort]
    let icon: NSImage?
    let usage: [Int32: ProcessUsage]
    let killStates: [String: KillState]
    let hoveredRow: String?
    let groupHeaderHeight: CGFloat
    let subRowHeight: CGFloat
    let onHover: (String, Bool) -> Void
    let onKill: (ListeningPort, Bool) -> Void

    private var lead: ListeningPort { ports[0] }

    /// CPU / memory summed across the group's *distinct* processes — several
    /// ports frequently share a single pid, so we mustn't double-count it.
    private var aggregateUsage: ProcessUsage? {
        var seen = Set<Int32>()
        var cpu = 0.0
        var mem: UInt64 = 0
        var any = false
        for port in ports where seen.insert(port.pid).inserted {
            if let u = usage[port.pid] {
                cpu += u.cpuPercent
                mem += u.memoryBytes
                any = true
            }
        }
        return any ? ProcessUsage(cpuPercent: cpu, memoryBytes: mem) : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(ports) { port in
                PortSubRow(
                    entry: port,
                    killState: killStates[port.id],
                    isHovered: hoveredRow == port.id,
                    height: subRowHeight,
                    onKill: { force in onKill(port, force) }
                )
                .onHover { onHover(port.id, $0) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            portIcon(icon, isContainer: lead.isContainer)
                .frame(width: 20, height: 20)
            Text(lead.displayName)
                .font(.lexend(12, .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .layoutPriority(1)
            if let secondary = fadedLabel(for: lead) {
                Text(secondary)
                    .font(.lexend(11))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
            }
            metaChip(for: lead)
            Spacer(minLength: 8)
            usageColumn(aggregateUsage)
        }
        .padding(.horizontal, 10)
        .frame(height: groupHeaderHeight)
    }
}

/// A single port beneath a group header: the port number, its address/pid and a
/// kill control, indented to sit under the header's name.
private struct PortSubRow: View {
    let entry: ListeningPort
    let killState: KillState?
    let isHovered: Bool
    let height: CGFloat
    let onKill: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: ":\(entry.port)")
                .font(.lexend(12.5, .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 60, alignment: .leading)
            Text("\(entry.addressSummary)   pid \(entry.pid)")
                .font(.lexend(10).monospacedDigit())
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(1)
            Spacer(minLength: 8)
            killControl(killState: killState, isHovered: isHovered,
                        port: entry.port, name: entry.displayName, onKill: onKill)
        }
        .padding(.leading, 30)
        .padding(.trailing, 10)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.white.opacity(isHovered ? 0.07 : 0))
        )
    }
}

// MARK: - Shared row pieces (used by both PortRow and grouped views)

private let portMemFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .memory
    formatter.allowedUnits = [.useMB, .useGB]
    return formatter
}()

private func cpuText(_ value: Double) -> String {
    value < 10 ? String(format: "%.1f%%", value) : String(format: "%.0f%%", value)
}

private func memoryText(_ bytes: UInt64) -> String {
    portMemFormatter.string(fromByteCount: Int64(bytes))
}

@ViewBuilder
private func portIcon(_ icon: NSImage?, isContainer: Bool) -> some View {
    if let icon {
        Image(nsImage: icon)
            .resizable()
            .frame(width: 20, height: 20)
    } else {
        Image(systemName: isContainer ? "shippingbox.fill" : "terminal.fill")
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.45))
            .frame(width: 20, height: 20)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.white.opacity(0.08))
            )
    }
}

/// Greyed-out text shown next to the primary name: the container runtime
/// (Docker/OrbStack) for container ports, otherwise the raw process name when it
/// differs from the resolved repo name.
private func fadedLabel(for entry: ListeningPort) -> String? {
    if entry.isContainer {
        guard let runtime = entry.containerRuntime, runtime != entry.displayName else { return nil }
        return runtime
    }
    return entry.displayName != entry.processName ? entry.processName : nil
}

/// Small muted icon+label chip (git branch or container service). Renders
/// nothing when neither applies.
@ViewBuilder
private func metaChip(for entry: ListeningPort) -> some View {
    if entry.isContainer {
        metaChipLabel(symbol: "shippingbox", text: entry.containerService ?? "container")
    } else if let branch = entry.gitBranch, !branch.isEmpty {
        metaChipLabel(symbol: "arrow.triangle.branch", text: branch)
    }
}

private func metaChipLabel(symbol: String, text: String) -> some View {
    HStack(spacing: 3) {
        Image(systemName: symbol)
            .font(.system(size: 8, weight: .semibold))
        Text(text)
            .font(.lexend(10, .medium))
            .lineLimit(1)
    }
    .foregroundStyle(.white.opacity(0.55))
}

private func usageColumn(_ usage: ProcessUsage?) -> some View {
    VStack(alignment: .trailing, spacing: 1) {
        Text(usage.map { cpuText($0.cpuPercent) } ?? "–")
            .font(.lexend(10.5, .medium).monospacedDigit())
            .foregroundStyle(
                (usage?.cpuPercent ?? 0) >= 90
                    ? Color.orange
                    : .white.opacity(0.7)
            )
        Text(usage.map { memoryText($0.memoryBytes) } ?? "–")
            .font(.lexend(9.5).monospacedDigit())
            .foregroundStyle(.white.opacity(0.35))
    }
    .frame(width: 56, alignment: .trailing)
}

@ViewBuilder
private func killControl(killState: KillState?, isHovered: Bool,
                         port: Int, name: String,
                         onKill: @escaping (Bool) -> Void) -> some View {
    switch killState {
    case .terminating(let since) where Date().timeIntervalSince(since) <= 3:
        ProgressView()
            .controlSize(.small)
            .frame(width: 22, height: 22)
    case .terminating:
        // SIGTERM didn't stick — offer the hammer.
        Button {
            onKill(true)
        } label: {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.red)
                .frame(width: 22, height: 22)
                .background(Circle().fill(.red.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .help("Still running — force kill (SIGKILL)")
    case .failed(let message):
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 11))
            .foregroundStyle(.yellow)
            .frame(width: 22, height: 22)
            .help(message)
    case nil:
        Button {
            onKill(NSEvent.modifierFlags.contains(.option))
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isHovered ? .white : .white.opacity(0.4))
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(isHovered ? Color.red.opacity(0.85) : .white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .help("Close port \(port) (kill \(name))")
    }
}

// MARK: - Small icon button

private struct IconButton: View {
    let symbol: String
    let help: String
    var isActive = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(
                    isActive ? Color.orange : .white.opacity(hovered ? 0.95 : 0.45)
                )
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(.white.opacity(hovered ? 0.12 : 0.05))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}
