import SwiftUI

struct ProgressBar: View {
    let progress: Double
    var gradient: LinearGradient = GradientTokens.workoutActive
    var tint: Color? = nil
    var track: Color = Color.white.opacity(0.16)

    private var clampedProgress: CGFloat {
        CGFloat(min(max(progress, 0), 1))
    }

    var body: some View {
        GeometryReader { geometry in
            let fillStyle = tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(gradient)
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(fillStyle)
                    .frame(width: geometry.size.width * clampedProgress)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.Size.progressBar)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(clampedProgress * 100)) percent")
    }
}

#Preview("Progress Bar") {
    ProgressBar(progress: 0.65)
        .padding()
        .background(ColorTokens.palette().backgroundPrimary)
}
