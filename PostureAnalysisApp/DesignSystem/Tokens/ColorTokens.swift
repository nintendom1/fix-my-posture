import SwiftUI

enum ColorAppearance: Sendable {
    case dark
    case light
}

struct ColorPalette {
    let brand: Color
    let accent: Color
    let success: Color
    let warning: Color
    let danger: Color
    let restInfo: Color
    let backgroundPrimary: Color
    let backgroundCard: Color
    let borderCard: Color
    let textPrimary: Color
    let textSecondary: Color
    let textMuted: Color
    let textSubtle: Color
    let tabActive: Color
    let tabPostureActive: Color
    let tabInactive: Color
    let hudToggleOff: Color
    let filterSelectedText: Color
    let filterUnselectedBackground: Color
    let filterUnselectedText: Color

    var allColors: [Color] {
        [brand, accent, success, warning, danger, restInfo, backgroundPrimary,
         backgroundCard, borderCard, textPrimary, textSecondary, textMuted,
         textSubtle, tabActive, tabPostureActive, tabInactive, hudToggleOff,
         filterSelectedText, filterUnselectedBackground, filterUnselectedText]
    }
}

struct WorkoutStateColors {
    let tint: Color
    let glow: Color
}

enum ColorTokens {
    private static let darkPalette = ColorPalette(
        brand: Color(hex: 0x7C4DFF),
        accent: Color(hex: 0xFF7F9E),
        success: Color(hex: 0x6EE7B7),
        warning: Color(hex: 0xFFC46B),
        danger: Color(hex: 0xFF7B8A),
        restInfo: Color(hex: 0x6FD6FF),
        backgroundPrimary: Color(hex: 0x0E0B16),
        backgroundCard: Color(hex: 0xFFFFFF, alpha: 0.06),
        borderCard: Color(hex: 0xFFFFFF, alpha: 0.07),
        textPrimary: Color(hex: 0xF6F3FB),
        textSecondary: Color(hex: 0xB9B0CC),
        textMuted: Color(hex: 0xA49CB8),
        textSubtle: Color(hex: 0x8A82A0),
        tabActive: Color(hex: 0xC9B3FF),
        tabPostureActive: Color(hex: 0x9FB0FF),
        tabInactive: Color(hex: 0x7D758C),
        hudToggleOff: Color(hex: 0xFF5A6E, alpha: 0.55),
        filterSelectedText: Color(hex: 0x1A1226),
        filterUnselectedBackground: Color(hex: 0xFFFFFF, alpha: 0.08),
        filterUnselectedText: Color(hex: 0xE4DDF0)
    )

    static func palette(for appearance: ColorAppearance = .dark) -> ColorPalette {
        switch appearance {
        case .dark, .light:
            return darkPalette
        }
    }

    static func workoutColors(
        for state: WorkoutVisualState,
        appearance: ColorAppearance = .dark
    ) -> WorkoutStateColors {
        let palette = palette(for: appearance)
        switch state.primary {
        case .ready:
            return WorkoutStateColors(tint: Color(hex: 0xB9A2FF), glow: Color(hex: 0x7C4DFF, alpha: 0.5))
        case .active:
            return WorkoutStateColors(tint: Color(hex: 0xB9A2FF), glow: Color(hex: 0x7C4DFF, alpha: 0.45))
        case .paused:
            return WorkoutStateColors(tint: Color(hex: 0xD8D0E8), glow: Color(hex: 0xC8BEE6, alpha: 0.25))
        case .tip, .tilt:
            return WorkoutStateColors(tint: palette.warning, glow: Color(hex: 0xFFB450, alpha: 0.45))
        case .rest:
            return WorkoutStateColors(tint: palette.restInfo, glow: Color(hex: 0x50BEFF, alpha: 0.45))
        case .lost:
            return WorkoutStateColors(tint: palette.danger, glow: Color(hex: 0xFF5A6E, alpha: 0.45))
        case .complete:
            return WorkoutStateColors(tint: palette.success, glow: Color(hex: 0x3CDC96, alpha: 0.55))
        }
    }
}

extension Color {
    init(hex value: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: alpha
        )
    }

    init?(hex string: String) {
        var digits = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        else if digits.lowercased().hasPrefix("0x") { digits.removeFirst(2) }

        let expanded: String
        switch digits.count {
        case 3, 4:
            expanded = digits.map { "\($0)\($0)" }.joined()
        case 6, 8:
            expanded = digits
        default:
            return nil
        }

        guard let value = UInt64(expanded, radix: 16) else { return nil }
        if expanded.count == 8 {
            self.init(
                hex: UInt32((value >> 8) & 0xFFFFFF),
                alpha: Double(value & 0xFF) / 255
            )
        } else {
            self.init(hex: UInt32(value))
        }
    }
}
