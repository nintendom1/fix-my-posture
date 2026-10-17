import SwiftUI

/// Five-point inset stroke with a soft, clipped inner glow around the camera view.
struct EdgeGlow: View {
    let tint: Color
    let glow: Color
    var isPulsing = true

    @Environment(\.motionPolicy) private var motionPolicy
    @State private var pulse = 0.0

    private let cornerRadius: CGFloat = 30
    private let inset: CGFloat = 5

    private var pulseAllowed: Bool {
        if case .full = motionPolicy { return isPulsing }
        return false
    }

    var body: some View {
        GeometryReader { geometry in
            let opacity = pulseAllowed ? 1 - pulse * 0.4 : 1.0
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(glow.opacity(0.65 * opacity), lineWidth: 70)
                .blur(radius: 24)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(tint.opacity(0.92 * opacity), lineWidth: inset)
                        .padding(inset)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { pulse = 1 }
        .animation(pulseAllowed ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : nil,
                   value: pulse)
    }
}
