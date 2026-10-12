import SwiftUI

/// A ring that fills while the start position is held, floating beside the body on whichever
/// side has more room. Standalone rather than part of the HUD.
struct HoldProgressRingView: View {
    let overlay: WorkoutOverlayState
    let progress: () -> Double?

    static let diameter: CGFloat = 72
    static let gap: CGFloat = 20

    var body: some View {
        TimelineView(.animation) { _ in
            GeometryReader { geometry in
                if let progress = progress(), let center = center(in: geometry.size) {
                    ring(progress)
                        .position(center)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Hold the start position")
                        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func ring(_ progress: Double) -> some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.55))
            Circle()
                .stroke(.white.opacity(0.25), lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(WorkoutJointOverlayView.endPositionColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("Hold")
                .font(.caption.bold())
                .foregroundStyle(.white)
        }
        .frame(width: Self.diameter, height: Self.diameter)
    }

    /// Chest height, just outside the body's widest visible joint on the roomier side.
    private func center(in size: CGSize) -> CGPoint? {
        let imageSize = overlay.imageSize
        let points = overlay.joints.values.filter { !$0.isStale }.map {
            CoordinateConverter.normalizedToContainer(normalized: $0.location, imageSize: imageSize, containerSize: size)
        }
        // From the side only one shoulder may be tracked.
        let shoulders = [overlay.joints[.leftShoulder], overlay.joints[.rightShoulder]].compactMap { $0 }.map {
            CoordinateConverter.normalizedToContainer(normalized: $0.location, imageSize: imageSize, containerSize: size)
        }
        guard !shoulders.isEmpty, let minX = points.map(\.x).min(), let maxX = points.map(\.x).max() else { return nil }
        let fit = CoordinateConverter.aspectFitRect(for: imageSize, in: size)
        let radius = Self.diameter / 2
        let rightRoom = fit.maxX - maxX
        let leftRoom = minX - fit.minX
        let x = rightRoom >= leftRoom ? maxX + Self.gap + radius : minX - Self.gap - radius
        let shoulderWidth = shoulders.count > 1 ? abs(shoulders[0].x - shoulders[1].x) : 0
        // Chest height: below the shoulders by a share of their width, or a fixed drop from the side.
        let drop = shoulders.count > 1 ? shoulderWidth * 0.6 : 40
        let y = shoulders.map(\.y).reduce(0, +) / CGFloat(shoulders.count) + drop
        return CGPoint(x: min(max(x, fit.minX + radius + 8), fit.maxX - radius - 8),
                       y: min(max(y, fit.minY + radius + 8), fit.maxY - radius - 8))
    }
}
