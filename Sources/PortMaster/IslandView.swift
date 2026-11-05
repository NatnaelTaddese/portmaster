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
    let openSettings: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    /// The notched island stays black in every theme: the fill camouflages the
    /// hardware notch. Elsewhere (external displays) it follows the appearance.
    private var palette: Palette {
        state.hasNotch ? .dark : Palette.resolve(colorScheme)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            island
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.palette, palette)
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
            islandShape.fill(palette.surface)

            if state.isExpanded {
                PortListContent(state: state, scanner: scanner, openSettings: openSettings)
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
            // The overscan grows the surface fill upward past the screen edge.
            height: state.currentIslandSize.height + IslandState.topOverscan
        )
        .clipShape(islandShape)
        .overlay(
            islandShape.strokeBorder(
                state.isExpanded ? palette.border : palette.borderCollapsed,
                lineWidth: 1
            )
        )
        .shadow(
            color: state.isExpanded ? palette.shadow : .clear,
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
            Button("Settings…") { openSettings() }
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
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(count > 0 ? palette.statusActive : palette.statusIdle)
                .frame(width: 5, height: 5)
            Text("\(count)")
                .font(.lexend(11, .semibold))
                .foregroundStyle(palette.textStrong)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Menu bar popover

/// Hosts the shared port list for the menu bar's `NSPopover` at a fixed width,
/// on the theme's solid surface color so it matches the island (the system
/// glass would tint it with whatever is behind). The popover's `NSAppearance`
/// (synced to the Theme setting) drives `colorScheme` here.
struct MenuBarPopoverView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var scanner: PortScanner
    let openSettings: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Palette.resolve(colorScheme)
        PortListContent(state: state, scanner: scanner, openSettings: openSettings, showsPin: false)
            .frame(width: state.expandedWidth)
            .background(palette.surface)
            .environment(\.palette, palette)
    }
}

// MARK: - Expanded

/// Header + port list + footer. Shared by the notch island and the menu bar
/// popover; the pin control only makes sense for the (hover-driven) notch.
struct PortListContent: View {
    @ObservedObject var state: IslandState
    @ObservedObject var scanner: PortScanner
    let openSettings: () -> Void
    var showsPin: Bool = true
    @State private var hoveredRow: String?
    @Environment(\.palette) private var palette

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
                .foregroundStyle(palette.textMuted)

            Spacer()

            // One glass capsule holding every header action, like a toolbar
            // island; the buttons inside are plain icons with a hover wash.
            HStack(spacing: 2) {
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
                IconButton(symbol: "gearshape", help: "Settings") {
                    openSettings()
                }
                IconButton(symbol: "power", help: "Quit PortMaster") {
                    NSApp.terminate(nil)
                }
            }
            .padding(3)
            .glassChip(Capsule(), fallback: palette.fillSubtle, interactive: false)
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

    /// One owner group. A single port renders as a plain row; several ports that
    /// share an owner are wrapped in a subtle container so it reads as one app.
    @ViewBuilder
    private func groupView(_ group: [ListeningPort]) -> some View {
        if group.count == 1 {
            row(group[0])
        } else {
            VStack(spacing: 0) {
                ForEach(group) { row($0) }
            }
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(palette.fillSubtle)
            )
            .padding(.vertical, 3)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.lexend(9.5, .semibold))
                .foregroundStyle(palette.textTertiary)
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
                .foregroundStyle(palette.textFaint)
            Text("No listening ports")
                .font(.lexend(12, .medium))
                .foregroundStyle(palette.textMuted)
        }
        .frame(maxWidth: .infinity)
        .frame(height: state.listHeight)
    }

    private var footer: some View {
        HStack {
            Text("⌥-click ✕ to force kill")
                .font(.lexend(9.5))
                .foregroundStyle(palette.textFaint)
            Spacer()
            Text("TCP · LISTEN")
                .font(.lexend(9, .medium))
                .foregroundStyle(palette.textFaint)
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
    @State private var showsCopied = false
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            portIcon(icon, isContainer: entry.isContainer, palette: palette)
                .frame(width: 20, height: 20)

            Text(verbatim: ":\(entry.port)")
                .font(.lexend(13, .semibold).monospacedDigit())
                .foregroundStyle(palette.textPrimary)
                .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(entry.displayName)
                        .font(.lexend(12, .medium))
                        .foregroundStyle(palette.textStrong)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let secondary = fadedLabel(for: entry) {
                        Text(secondary)
                            .font(.lexend(11))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 5) {
                    metaChip(for: entry, palette: palette)
                    Text("\(entry.addressSummary)   pid \(entry.pid)")
                        .font(.lexend(10).monospacedDigit())
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            usageColumn(usage, palette: palette)

            killControl(killState: killState, isHovered: isHovered,
                        port: entry.port, name: entry.displayName,
                        palette: palette, onKill: onKill)
        }
        .padding(.horizontal, 10)
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovered ? palette.fillHover : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture {
            if entry.isDevServer {
                if let url = URL(string: "http://localhost:\(entry.port)") {
                    NSWorkspace.shared.open(url)
                }
            } else {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString("localhost:\(entry.port)", forType: .string)
                withAnimation(.easeOut(duration: 0.15)) { showsCopied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeOut(duration: 0.3)) { showsCopied = false }
                }
            }
        }
        .overlay {
            if showsCopied {
                Text("Copied localhost:\(entry.port)")
                    .font(.lexend(10, .semibold))
                    .foregroundStyle(palette.textStrong)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .glassChip(Capsule(), fallback: palette.fillToast, interactive: false)
                    .transition(.opacity)
            }
        }
        .help(entry.isDevServer
              ? "Open http://localhost:\(entry.port)"
              : "Copy localhost:\(entry.port)")
    }

}

// MARK: - Shared row pieces

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
private func portIcon(_ icon: NSImage?, isContainer: Bool, palette: Palette) -> some View {
    if let icon {
        Image(nsImage: icon)
            .resizable()
            .frame(width: 20, height: 20)
    } else {
        Image(systemName: isContainer ? "shippingbox.fill" : "terminal.fill")
            .font(.system(size: 11))
            .foregroundStyle(palette.iconIdle)
            .frame(width: 20, height: 20)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(palette.fillControl)
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
private func metaChip(for entry: ListeningPort, palette: Palette) -> some View {
    if entry.isContainer {
        metaChipLabel(symbol: "shippingbox", text: entry.containerService ?? "container",
                      palette: palette)
    } else if let branch = entry.gitBranch, !branch.isEmpty {
        metaChipLabel(symbol: "arrow.triangle.branch", text: branch, palette: palette)
    }
}

private func metaChipLabel(symbol: String, text: String, palette: Palette) -> some View {
    HStack(spacing: 3) {
        Image(systemName: symbol)
            .font(.system(size: 8, weight: .semibold))
        Text(text)
            .font(.lexend(10, .medium))
            .lineLimit(1)
    }
    .foregroundStyle(palette.textMuted)
}

private func usageColumn(_ usage: ProcessUsage?, palette: Palette) -> some View {
    VStack(alignment: .trailing, spacing: 1) {
        Text(usage.map { cpuText($0.cpuPercent) } ?? "–")
            .font(.lexend(10.5, .medium).monospacedDigit())
            .foregroundStyle(
                (usage?.cpuPercent ?? 0) >= 90 ? palette.accent : palette.textSecondary
            )
        Text(usage.map { memoryText($0.memoryBytes) } ?? "–")
            .font(.lexend(9.5).monospacedDigit())
            .foregroundStyle(palette.textTertiary)
    }
    .frame(width: 56, alignment: .trailing)
}

@ViewBuilder
private func killControl(killState: KillState?, isHovered: Bool,
                         port: Int, name: String, palette: Palette,
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
                .foregroundStyle(palette.danger)
                .frame(width: 22, height: 22)
                .glassChip(Circle(), fallback: palette.dangerFill, tint: palette.dangerFill)
        }
        .buttonStyle(.plain)
        .help("Still running — force kill (SIGKILL)")
    case .failed(let message):
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 11))
            .foregroundStyle(palette.warning)
            .frame(width: 22, height: 22)
            .help(message)
    case nil:
        Button {
            onKill(NSEvent.modifierFlags.contains(.option))
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isHovered ? palette.onDanger : palette.iconIdle)
                .frame(width: 22, height: 22)
                .glassChip(
                    Circle(),
                    fallback: isHovered ? palette.dangerFillHover : palette.fillControl,
                    tint: isHovered ? palette.dangerFillHover : nil
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
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(
                    isActive ? palette.accent : (hovered ? palette.textPrimary : palette.iconIdle)
                )
                .frame(width: 26, height: 26)
                .background(Circle().fill(hovered ? palette.fillControlHover : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}
