import SwiftUI

struct EmptyStateTile: View {
    let title: String
    let message: String
    let icon: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Metrics.Spacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(ColorTokens.palette().tabActive)
                .frame(width: 48, height: 48)
                .background(ColorTokens.palette().brand.opacity(0.16), in: RoundedRectangle(cornerRadius: Metrics.Radius.thumbnail))

            VStack(spacing: Metrics.Spacing.xSmall) {
                Text(title)
                    .textStyle(.headline)
                    .foregroundStyle(ColorTokens.palette().textPrimary)
                Text(message)
                    .textStyle(.caption1)
                    .foregroundStyle(ColorTokens.palette().textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                CapsuleButton(title: actionTitle, action: action)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Metrics.Spacing.large)
        .background {
            RoundedRectangle(cornerRadius: Metrics.Radius.card)
                .fill(ColorTokens.palette().backgroundCard)
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.Radius.card)
                        .strokeBorder(ColorTokens.palette().borderCard, lineWidth: 1)
                }
        }
    }
}

#Preview("Empty State Tile") {
    ZStack {
        ColorTokens.palette().backgroundPrimary.ignoresSafeArea()
        EmptyStateTile(
            title: "No sets yet",
            message: "Save a routine to get started.",
            icon: "dumbbell.fill",
            actionTitle: "Create Routine",
            action: {}
        )
        .padding(.horizontal, Metrics.Spacing.screenMargin)
    }
}
