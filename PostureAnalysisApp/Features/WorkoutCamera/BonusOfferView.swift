import AdaptiveTraining
import SwiftUI

/// The open "Want one more?" offer after a prescribed item rated Easy: what one more is, until it is taken or declined.
/// It never pauses the workout: starting the next set closes it as declined.
struct BonusOfferState: Equatable, Identifiable {
    /// The id of the evidence recorded when the offer is settled, so a retried save can't record it twice.
    let id: UUID
    /// One more rep, or a few more seconds of a hold.
    let offered: Dose

    /// "1 rep" or "5 s".
    var amountLabel: String { WorkAmount(offered).description }
}

/// A large, tap-friendly card in the same place as the effort card. Declining is a full success with no penalty, so
/// "I'm done" is as easy to reach as "One more".
struct BonusOfferView: View {
    let state: BonusOfferState
    /// Say that the two answers can also be spoken.
    let showsVoiceHint: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void

    private let palette = ColorTokens.palette()

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 96)
                .allowsHitTesting(false)
            card
            Spacer(minLength: 0)
                .allowsHitTesting(false)
            // The bottom controls (Start, Done, rest) stay reachable.
            Spacer()
                .frame(height: 196)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var card: some View {
        VStack(spacing: 14) {
            Text("That felt easy. Want one more?")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("+\(state.amountLabel), just if you like")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textSecondary)
                .accessibilityLabel("An optional extra \(state.amountLabel)")

            HStack(spacing: 10) {
                answerButton("One more", tint: palette.success, action: onAccept,
                             hint: "Do \(state.amountLabel) more as an optional extra.",
                             identifier: "bonusAcceptButton")
                answerButton("I\u{2019}m done", tint: palette.tabActive, action: onDecline,
                             hint: "Finish here. What you did already counts in full.",
                             identifier: "bonusDeclineButton")
            }

            if showsVoiceHint {
                Text("Or say \u{201C}one more\u{201D} or \u{201C}I\u{2019}m done\u{201D}.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(Color(hex: 0x1A1526), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(palette.borderCard, lineWidth: 1))
        .padding(.horizontal, 24)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bonusOfferCard")
    }

    private func answerButton(_ title: String, tint: Color, action: @escaping () -> Void, hint: String,
                              identifier: String) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 68)
                .background(tint.opacity(0.22), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(tint, lineWidth: 2))
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
    }
}
