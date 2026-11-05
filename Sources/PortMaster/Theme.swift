import AppKit
import SwiftUI

/// User-selected appearance, persisted in IslandState. `.system` follows macOS.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// Appearance to assign to a window/popover; nil inherits the system one.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

/// Semantic colors for the island / popover chrome. `.dark` is the original
/// hardcoded look; `.light` retunes alphas since black tints on an off-white
/// surface read stronger than white tints on black.
struct Palette {
    // Surfaces
    let surface: Color
    let border: Color
    let borderCollapsed: Color
    let shadow: Color

    // Text, bright → faint
    let textPrimary: Color
    let textStrong: Color
    let textSecondary: Color
    let textMuted: Color
    let iconIdle: Color
    let textTertiary: Color
    let textFaint: Color

    // Fills
    let fillSubtle: Color
    let fillHover: Color
    let fillControl: Color
    let fillControlHover: Color
    let fillToast: Color

    // Accents
    let statusActive: Color
    let statusIdle: Color
    let accent: Color
    let danger: Color
    let dangerFill: Color
    let dangerFillHover: Color
    let onDanger: Color
    let warning: Color

    static let dark = Palette(
        surface: .black,
        border: .white.opacity(0.10),
        borderCollapsed: .white.opacity(0.05),
        shadow: .black.opacity(0.55),
        textPrimary: .white,
        textStrong: .white.opacity(0.92),
        textSecondary: .white.opacity(0.70),
        textMuted: .white.opacity(0.55),
        iconIdle: .white.opacity(0.45),
        textTertiary: .white.opacity(0.35),
        textFaint: .white.opacity(0.28),
        fillSubtle: .white.opacity(0.05),
        fillHover: .white.opacity(0.07),
        fillControl: .white.opacity(0.08),
        fillControlHover: .white.opacity(0.12),
        fillToast: .white.opacity(0.14),
        statusActive: .green,
        statusIdle: .gray,
        accent: .orange,
        danger: .red,
        dangerFill: .red.opacity(0.18),
        dangerFillHover: .red.opacity(0.85),
        onDanger: .white,
        warning: .yellow
    )

    static let light = Palette(
        surface: Color(white: 0.96),
        border: .black.opacity(0.12),
        borderCollapsed: .black.opacity(0.08),
        shadow: .black.opacity(0.22),
        textPrimary: .black.opacity(0.90),
        textStrong: .black.opacity(0.80),
        textSecondary: .black.opacity(0.65),
        textMuted: .black.opacity(0.55),
        iconIdle: .black.opacity(0.45),
        textTertiary: .black.opacity(0.40),
        textFaint: .black.opacity(0.32),
        fillSubtle: .black.opacity(0.04),
        fillHover: .black.opacity(0.05),
        fillControl: .black.opacity(0.06),
        fillControlHover: .black.opacity(0.10),
        fillToast: .black.opacity(0.10),
        statusActive: .green,
        statusIdle: .gray,
        accent: .orange,
        danger: .red,
        dangerFill: .red.opacity(0.15),
        dangerFillHover: .red.opacity(0.85),
        onDanger: .white,
        // Pure yellow is illegible on off-white.
        warning: Color(red: 0.80, green: 0.55, blue: 0)
    )

    static func resolve(_ scheme: ColorScheme) -> Palette {
        scheme == .dark ? .dark : .light
    }
}

private struct PaletteKey: EnvironmentKey {
    // Default to the original dark look so un-rooted previews stay unchanged.
    static let defaultValue = Palette.dark
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}
