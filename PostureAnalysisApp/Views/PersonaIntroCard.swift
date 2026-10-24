import SwiftUI

/// A one-time card introducing Extra Personable, shown on the Posture and Train tabs until dismissed.
struct PersonaIntroCard: View {
    let onDismiss: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        let palette = ColorTokens.palette()

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("She’s paying attention now")
                        .font(Typography.title)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("She may occasionally notice progress, habits, and patterns from your workout and posture history.")
                        .font(Typography.body)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image("NotificationCharacter/smile-hoodie-portrait")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)
            }

            HStack(spacing: 10) {
                Button("Got it", action: onDismiss)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 38)
                    .background(palette.brand, in: Capsule())
                    .accessibilityIdentifier("personaIntroDismiss")

                Button("Settings", action: onOpenSettings)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.tabActive)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 38)
                    .accessibilityIdentifier("personaIntroSettings")

                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(
            palette.backgroundCard,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(palette.borderCard, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("personaIntroCard")
    }
}
