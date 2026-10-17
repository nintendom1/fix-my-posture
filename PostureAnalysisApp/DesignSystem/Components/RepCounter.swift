import SwiftUI

/// The current state label and a large rep count (or rest countdown) with its target.
struct RepCounter: View {
    let stateLabel: String
    let count: String
    let target: String?
    let tint: Color
    var repEventCount = 0
    var isResting = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var repPulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: isResting ? -8 : -12) {
            Text(stateLabel.uppercased())
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundStyle(tint)
                .lineLimit(1)
                .designAnchor("camera.stateLabel")

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(count)
                    .font(isResting
                          ? .system(size: 84, weight: .heavy, design: .rounded)
                          : Typography.repCounter)
                    .tracking(isResting ? -1.7 : -3)
                    .monospacedDigit()
                    .foregroundStyle(ColorTokens.palette().textPrimary)
                    .contentTransition(.numericText())
                    .scaleEffect(repPulse ? 1.08 : 1, anchor: .bottomLeading)
                    .designAnchor("camera.repCount")
                    .accessibilityLabel(isResting ? "Rest countdown \(count)" : "\(count) reps")

                if let target {
                    Text(target)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .onChange(of: repEventCount) { oldValue, newValue in
                guard newValue > oldValue, !reduceMotion else { return }
                withAnimation(.spring(response: 0.18, dampingFraction: 0.52)) { repPulse = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) { repPulse = false }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
