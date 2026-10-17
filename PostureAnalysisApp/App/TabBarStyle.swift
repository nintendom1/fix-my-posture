import Foundation

struct TabBarColor: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(hex: UInt32, alpha: Double = 1) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    var hex: UInt32 {
        (UInt32((red * 255).rounded()) << 16)
            | (UInt32((green * 255).rounded()) << 8)
            | UInt32((blue * 255).rounded())
    }
}

struct TabBarTitleFont: Equatable {
    enum Weight: Equatable { case heavy }

    let pointSize: Double
    let weight: Weight
    let rounded: Bool
}

/// UIKit-independent tab bar values so the visual contract can be tested directly.
struct TabBarStyle: Equatable {
    enum Blur: Equatable { case darkMaterial }

    let background: TabBarColor
    let backgroundBlur: Blur
    let hairlineColor: TabBarColor
    let inactiveColor: TabBarColor
    let titleFont: TabBarTitleFont

    static let design = TabBarStyle(
        background: TabBarColor(hex: 0x120E1C, alpha: 0.84),
        backgroundBlur: .darkMaterial,
        hairlineColor: TabBarColor(hex: 0xFFFFFF, alpha: 0.06),
        inactiveColor: TabBarColor(hex: 0x7D758C),
        titleFont: TabBarTitleFont(pointSize: 11, weight: .heavy, rounded: true)
    )

    func tintHex(for tab: AppTab) -> UInt32 {
        tab == .posture ? 0x9FB0FF : 0xC9B3FF
    }
}
