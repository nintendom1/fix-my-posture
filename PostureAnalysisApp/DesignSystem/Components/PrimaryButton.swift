import SwiftUI

struct PrimaryButton: View {
    enum Variant {
        case gradient
        case white
    }

    enum Size {
        case standard
        case sticky

        var height: CGFloat {
            switch self {
            case .standard: return Metrics.Size.primaryCTA
            case .sticky: return Metrics.Size.stickyCTA
            }
        }
    }

    let title: String
    var icon: String? = nil
    var iconFontSize: CGFloat = 24
    var contentSpacing: CGFloat = Metrics.Spacing.xSmall
    var variant: Variant = .gradient
    var size: Size = .standard
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: contentSpacing) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: iconFontSize, weight: .bold, design: .rounded))
                }
                Text(title)
                    .font(.system(size: 18, weight: .black, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .frame(height: size.height)
            .foregroundStyle(foregroundColor)
            .background(background)
            .clipShape(Capsule())
            .shadow(color: shadowColor, radius: 14, x: 0, y: 7)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var background: some View {
        switch variant {
        case .gradient:
            GradientTokens.trainHero
        case .white:
            Color.white
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .gradient: return .white
        case .white: return Color(hex: 0x4A23C9)
        }
    }

    private var shadowColor: Color {
        switch variant {
        case .gradient: return Color(hex: 0x7C4DFF, alpha: 0.3)
        case .white: return .clear
        }
    }
}

#Preview("Primary Button · Gradient") {
    ZStack {
        ColorTokens.palette().backgroundPrimary.ignoresSafeArea()
        PrimaryButton(title: "Start Exercise", icon: "play.fill", action: {})
            .padding(.horizontal, Metrics.Spacing.screenMargin)
    }
}

#Preview("Primary Button · White") {
    ZStack {
        ColorTokens.palette().backgroundPrimary.ignoresSafeArea()
        PrimaryButton(title: "Start Routine", icon: "play.fill", variant: .white, action: {})
            .padding(.horizontal, Metrics.Spacing.screenMargin)
    }
}
