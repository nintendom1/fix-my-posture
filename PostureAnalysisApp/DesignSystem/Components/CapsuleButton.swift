import SwiftUI

struct CapsuleButton: View {
    let title: String
    var icon: String? = nil
    var tint: Color = ColorTokens.palette().textPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.Spacing.xSmall) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                Text(title)
                    .font(.system(size: 14, weight: .black, design: .rounded))
            }
            .padding(.horizontal, Metrics.Spacing.medium)
            .frame(minHeight: Metrics.Size.capsuleButtonVisual)
            .background(ColorTokens.palette().backgroundPrimary.opacity(0.55), in: Capsule())
            .foregroundStyle(tint)
            .frame(minHeight: Metrics.Size.tapTarget)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Capsule Button") {
    ZStack {
        ColorTokens.palette().backgroundPrimary.ignoresSafeArea()
        CapsuleButton(title: "How to Do It", icon: "info.circle", action: {})
    }
}
