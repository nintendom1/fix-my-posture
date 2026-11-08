import SwiftUI

/// Copy for the launch invitation, kept together for the wording scan.
enum AdaptiveInvitationCopy {
    static let title = "Adaptive Training"
    static let body = "Find a comfortable starting point in a few minutes. A few tiny samples, then a short session each day."
    static let findStartingPoint = "Find your starting point"
    static let notNow = "Not now"

    static let all = [title, body, findStartingPoint, notNow]
}

/// Invites the user to find a starting point before the first session.
struct AdaptiveInvitationSheet: View {
    let onAccept: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(AdaptiveInvitationCopy.title)
                    .font(Typography.title)
                    .foregroundStyle(ColorTokens.palette().textPrimary)
                    .accessibilityIdentifier("adaptiveInvitationTitle")

                Text(AdaptiveInvitationCopy.body)
                    .font(Typography.body)
                    .foregroundStyle(ColorTokens.palette().textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("adaptiveInvitationBody")
            }

            Spacer(minLength: 0)

            PrimaryButton(
                title: AdaptiveInvitationCopy.findStartingPoint,
                icon: "arrow.right",
                iconFontSize: 22,
                contentSpacing: 6
            ) {
                onAccept()
            }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("adaptiveInvitationFindStartingPoint")

            Button(AdaptiveInvitationCopy.notNow, action: onNotNow)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("adaptiveInvitationNotNow")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(hex: 0x1A1526))
        .accessibilityIdentifier("adaptiveInvitationSheet")
        .presentationDetents([.height(330)])
        .presentationCornerRadius(28)
        .presentationBackground(Color(hex: 0x1A1526))
        .presentationDragIndicator(.visible)
    }
}
