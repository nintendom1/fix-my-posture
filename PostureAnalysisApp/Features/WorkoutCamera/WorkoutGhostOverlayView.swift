import SwiftUI

/// Ghost arms that loop the guide's motion over the user's own body before the set starts, fitted to
/// their shoulders and arm lengths. Aspect-fit scaling is uniform, so angles computed in container
/// points stay correct.
struct WorkoutGhostOverlayView: View {
    let overlay: WorkoutOverlayState
    let metrics: GuideMetrics?
    let motion: ArmMotion
    var cameraView: ExerciseCameraView = .front

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let ghostColor = Color(red: 0.76, green: 0.59, blue: 1)

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                draw(in: context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(in context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let imageSize = overlay.imageSize
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let fit = CoordinateConverter.aspectFitRect(for: imageSize, in: size)
        guard fit.width > 0 else { return }

        var context = context
        context.clip(to: Path(fit))
        if reduceMotion {
            draw(geometry(for: motion.topAngles, legs: motion.topLegs, size: size),
                 in: context, opacity: 0.3)
            draw(geometry(for: motion.startAngles, legs: motion.startLegs, size: size),
                 in: context, opacity: 0.6)
        } else {
            let sample = motion.sample(at: time)
            draw(geometry(for: sample.angles, legs: sample.legs, size: size), in: context, opacity: 0.6)
        }
    }

    private func geometry(for angles: ArmAngles, legs: LegPose, size: CGSize) -> WorkoutGhostGeometry {
        WorkoutGhostGeometry.make(overlay: overlay, metrics: metrics, motion: motion, cameraView: cameraView,
                                  containerSize: size, angles: angles, legs: legs)
    }

    private func draw(_ geometry: WorkoutGhostGeometry, in context: GraphicsContext, opacity: Double) {
        for limb in geometry.limbs {
            guard let first = limb.points.first else { continue }
            var path = Path()
            path.move(to: first)
            for point in limb.points.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(path, with: .color(Self.ghostColor.opacity(opacity)),
                           style: StrokeStyle(lineWidth: limb.lineWidth, lineCap: .round, lineJoin: .round))

            if limb.holdsDumbbell, limb.points.count >= 3 {
                var dumbbell = context
                dumbbell.opacity = opacity + 0.2
                DumbbellDrawing.draw(in: dumbbell, elbow: limb.points[1], wrist: limb.points[2],
                                     forearmLength: geometry.forearmLength)
            }
        }

        if let connector = geometry.connector, let first = connector.points.first {
            var path = Path()
            path.move(to: first)
            for point in connector.points.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(path, with: .color(Self.ghostColor.opacity(opacity)),
                           style: StrokeStyle(lineWidth: connector.lineWidth, lineCap: .round))
        }
    }
}
