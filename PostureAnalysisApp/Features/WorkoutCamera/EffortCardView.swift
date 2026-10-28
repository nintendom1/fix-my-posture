import AdaptiveTraining
import SwiftUI

/// The open "How was that?" question about a finished item: the amount it will record and how the user rates it.
struct EffortCardState: Equatable, Identifiable {
    /// The id of the evidence the answer will record, so a retried save can't record it twice.
    let id: UUID
    let unit: DoseKind
    /// How many sets the amount stands for; more than one reads "each set".
    let setCount: Int
    /// The amount the card opened with: counted reps, the recorded amount, or 0 for a skipped item.
    let defaultAmount: Int
    var amount: Int
    /// The card asks about the optional bonus set the user took, not about a prescribed item.
    let isBonus: Bool

    static let maximumAmount = 999

    init(id: UUID, unit: DoseKind, setCount: Int, amount: Int, isBonus: Bool = false) {
        self.id = id
        self.unit = unit
        self.setCount = max(1, setCount)
        defaultAmount = max(0, amount)
        self.amount = max(0, amount)
        self.isBonus = isBonus
    }

    var title: String { isBonus ? "How was the bonus?" : "How was that?" }

    /// Reps change by 1, seconds by 5.
    var step: Int { unit == .seconds ? 5 : 1 }
    var isAdjusted: Bool { amount != defaultAmount }
    /// "3 reps" or "20 s".
    var amountLabel: String { WorkAmount(kind: unit, amount: amount).description }

    mutating func adjust(by steps: Int) {
        amount = min(Self.maximumAmount, max(0, amount + steps * step))
    }
}

/// A large, tap-friendly card over the camera. It sits above the workout controls, never over them, so the next set can
/// start while it is open.
struct EffortCardView: View {
    let state: EffortCardState
    /// Say that the three answers can also be spoken.
    let showsVoiceHint: Bool
    let onAdjust: (Int) -> Void
    let onRate: (EffortFeedback) -> Void
    let onSkip: () -> Void

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
            Text(state.title)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            amountRow

            HStack(spacing: 10) {
                ratingButton("Too Hard", effort: .tooHard, tint: palette.warning,
                             hint: "Rate what you just did as too hard.", identifier: "effortTooHardButton")
                ratingButton("Okay", effort: .okay, tint: palette.tabActive,
                             hint: "Rate what you just did as about right.", identifier: "effortOkayButton")
                ratingButton("Easy", effort: .easy, tint: palette.success,
                             hint: "Rate what you just did as easy.", identifier: "effortEasyButton")
            }

            if showsVoiceHint {
                Text("Or say “too hard”, “okay”, or “easy”.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.textMuted)
                    .multilineTextAlignment(.center)
            }

            Button(action: onSkip) {
                Text("Skip")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textSecondary)
                    .frame(minWidth: 88, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip")
            .accessibilityHint("Closes this question without rating what you just did.")
            .accessibilityIdentifier("effortSkipButton")
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(Color(hex: 0x1A1526), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(palette.borderCard, lineWidth: 1))
        .padding(.horizontal, 24)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(state.isBonus ? "bonusRatingCard" : "effortCard")
    }

    private var amountRow: some View {
        HStack(spacing: 14) {
            adjustButton(systemImage: "minus", label: "Decrease amount", steps: -1, identifier: "effortDecreaseButton")
                .disabled(state.amount == 0)
            VStack(spacing: 2) {
                Text(state.amountLabel)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if state.setCount > 1 {
                    Text("each set")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(palette.textMuted)
                }
            }
            .frame(minWidth: 110)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Amount: \(state.amountLabel)\(state.setCount > 1 ? " each set" : "")")
            adjustButton(systemImage: "plus", label: "Increase amount", steps: 1, identifier: "effortIncreaseButton")
                .disabled(state.amount >= EffortCardState.maximumAmount)
        }
    }

    private func adjustButton(systemImage: String, label: String, steps: Int, identifier: String) -> some View {
        Button { onAdjust(steps) } label: {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 52, height: 52)
                .background(Color.white.opacity(0.1), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint("Changes the amount by \(state.step) \(state.unit == .seconds ? "seconds" : state.step == 1 ? "rep" : "reps").")
        .accessibilityIdentifier(identifier)
    }

    private func ratingButton(_ title: String, effort: EffortFeedback, tint: Color, hint: String,
                              identifier: String) -> some View {
        Button { onRate(effort) } label: {
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
