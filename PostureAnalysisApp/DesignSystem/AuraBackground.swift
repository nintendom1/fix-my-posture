import SwiftUI

struct AuraBackground: View {
    enum Tab: String, CaseIterable {
        case train
        case routines
        case progress
        case posture
        case complete
        case settings
    }

    @Environment(\.motionPolicy) private var motionPolicy
    let tab: Tab

    private var auraColors: (first: Color, second: Color) {
        switch tab {
        case .train, .settings:
            return (Color(hex: 0x7C4DFF, alpha: 0.55), Color(hex: 0xFF6EAA, alpha: 0.28))
        case .routines:
            return (Color(hex: 0x7C4DFF, alpha: 0.45), Color(hex: 0xFF8C5A, alpha: 0.2))
        case .progress:
            return (Color(hex: 0x6450FF, alpha: 0.5), Color(hex: 0x2FB8A0, alpha: 0.28))
        case .posture:
            return (Color(hex: 0x4664FF, alpha: 0.5), Color(hex: 0x56B8D8, alpha: 0.28))
        case .complete:
            return (Color(hex: 0x22C38E, alpha: 0.45), Color(hex: 0x7C4DFF, alpha: 0.3))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let colors = auraColors
            ZStack(alignment: .topLeading) {
                ColorTokens.palette().backgroundPrimary

                Circle()
                    .fill(auraBlob(color: colors.first, radius: 154))
                    .frame(width: 440, height: 440)
                    .offset(x: -150, y: -140)

                Circle()
                    .fill(auraBlob(color: colors.second, radius: 140))
                    .frame(width: 400, height: 400)
                    .offset(x: geometry.size.width - 230, y: 240)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(motionPolicy == .reduced ? nil : .easeInOut(duration: 0.5), value: tab)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func auraBlob(color: Color, radius: CGFloat) -> RadialGradient {
        RadialGradient(
            colors: [color, color.opacity(0)],
            center: .center,
            startRadius: 0,
            endRadius: radius
        )
    }
}

#Preview("Train Aura") {
    AuraBackground(tab: .train)
}
