import SwiftUI

/// The open "Too hard?" offer during a set: what the user can do about it. It never pauses or stops the set; ignoring
/// it, or closing it, keeps the set going.
struct TooHardOfferState: Equatable, Identifiable {
    /// The easier version the engine chose, ready to run.
    struct EasierVersion: Equatable {
        /// The exercise's name at the range it will run ("Shallow Wall Push-Up").
        let name: String
        /// "3 reps" or "15 s".
        let amountLabel: String
    }

    let id: UUID
    /// Nil when the engine has no easier version (or this item can't swap), so only "Stop here" is offered.
    var easierVersion: EasierVersion?
}

/// A small card above the bottom controls. It is non-blocking: the camera and the controls under it stay usable, and the
/// card closes by itself when the set ends.
struct TooHardOfferView: View {
    let state: TooHardOfferState
    let onStopHere: () -> Void
    let onEasierVersion: () -> Void
    let onDismiss: () -> Void

    private let palette = ColorTokens.palette()

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
                .allowsHitTesting(false)
            card
            // The bottom controls (Done, Pause, rest) stay reachable.
            Spacer()
                .frame(height: 196)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var card: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Too hard? Your set keeps going.")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityHint("Closes this offer. Your set keeps going.")
                .accessibilityIdentifier("tooHardDismissButton")
            }

            HStack(spacing: 10) {
                optionButton("Stop here, it counts", detail: "Ends it with what you did.", tint: palette.warning,
                             hint: "Ends this exercise now. What you did so far counts.",
                             identifier: "tooHardStopButton", action: onStopHere)
                if let easier = state.easierVersion {
                    optionButton("Easier version", detail: "\(easier.name) · \(easier.amountLabel)",
                                 tint: palette.success,
                                 hint: "Ends this exercise with what you did, then does \(easier.amountLabel) of "
                                     + "\(easier.name) instead.",
                                 identifier: "tooHardEasierButton", action: onEasierVersion)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .padding(.top, 6)
        .frame(maxWidth: 360)
        .background(Color(hex: 0x1A1526), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(palette.borderCard, lineWidth: 1))
        .padding(.horizontal, 24)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tooHardOfferCard")
        .background(GeometryReader { proxy in
            Color.clear.preference(key: WorkoutHUDRects.self,
                                   value: [proxy.frame(in: .named(WorkoutCoachView.coordinateSpace))])
        })
    }

    private func optionButton(_ title: String, detail: String, tint: Color, hint: String, identifier: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                Text(detail)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.horizontal, 6)
            .background(tint.opacity(0.22), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
    }
}
