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
                ExpandedContent(state: state, scanner: scanner)
                    .padding(.top, state.notchHeight)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else if !state.hasNotch {
                CollapsedPill(count: state.portCount)
            }
        }
        .frame(
            width: state.currentIslandSize.width,
            height: state.currentIslandSize.height
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

// MARK: - Expanded

private struct ExpandedContent: View {
    @ObservedObject var state: IslandState
    @ObservedObject var scanner: PortScanner
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
            IconButton(
                symbol: state.isPinned ? "pin.fill" : "pin",
                help: state.isPinned ? "Unpin" : "Keep open",
                isActive: state.isPinned
            ) {
                state.isPinned.toggle()
            }
            IconButton(symbol: "power", help: "Quit PortMaster") {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: state.headerHeight)
    }

    private var portList: some View {
        ScrollView(.vertical, showsIndicators: scanner.ports.count > state.maxVisibleRows) {
            LazyVStack(spacing: 0) {
                ForEach(scanner.ports) { entry in
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
            }
            .padding(.horizontal, 8)
        }
        .frame(height: state.listHeight)
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
            iconView
                .frame(width: 20, height: 20)

            Text(verbatim: ":\(entry.port)")
                .font(.lexend(13, .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayName)
                    .font(.lexend(12, .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                Text("\(entry.addressSummary)   pid \(entry.pid)")
                    .font(.lexend(10).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            usageColumn

            trailingControl
        }
        .padding(.horizontal, 10)
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.white.opacity(isHovered ? 0.07 : 0))
        )
    }

    private var usageColumn: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(usage.map { Self.cpuText($0.cpuPercent) } ?? "–")
                .font(.lexend(10.5, .medium).monospacedDigit())
                .foregroundStyle(
                    (usage?.cpuPercent ?? 0) >= 90
                        ? Color.orange
                        : .white.opacity(0.7)
                )
            Text(usage.map { Self.memoryText($0.memoryBytes) } ?? "–")
                .font(.lexend(9.5).monospacedDigit())
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(width: 56, alignment: .trailing)
    }

    private static func cpuText(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f%%", value) : String(format: "%.0f%%", value)
    }

    private static let memFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useMB, .useGB]
        return formatter
    }()

    private static func memoryText(_ bytes: UInt64) -> String {
        memFormatter.string(fromByteCount: Int64(bytes))
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: "terminal.fill")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.white.opacity(0.08))
                )
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
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
            .help("Close port \(entry.port) (kill \(entry.displayName))")
        }
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
