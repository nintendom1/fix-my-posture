import SwiftUI

/// Ghost arms that loop the guide's motion over the user's own body before the set starts, fitted to
/// their shoulders and arm lengths. Aspect-fit scaling is uniform, so angles computed in container
/// points stay correct.
struct WorkoutGhostOverlayView: View {
    let overlay: WorkoutOverlayState
    let metrics: GuideMetrics
    let motion: ArmMotion

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
        guard imageSize.width > 0, imageSize.height > 0,
              let left = overlay.joints[.leftShoulder], !left.isStale,
              let right = overlay.joints[.rightShoulder], !right.isStale else { return }
        let fit = CoordinateConverter.aspectFitRect(for: imageSize, in: size)
        guard fit.width > 0 else { return }
        let scale = fit.width / imageSize.width
        let shoulders = [left, right].map {
            CoordinateConverter.normalizedToContainer(normalized: $0.location, imageSize: imageSize, containerSize: size)
        }
        var context = context
        context.clip(to: Path(fit))
        let arms = (upper: metrics.upperArm * scale, fore: metrics.forearm * scale)
        if reduceMotion {
            drawArms(in: context, shoulders: shoulders, arms: arms, angles: motion.topAngles, opacity: 0.3)
            drawArms(in: context, shoulders: shoulders, arms: arms, angles: motion.startAngles, opacity: 0.6)
        } else {
            drawArms(in: context, shoulders: shoulders, arms: arms, angles: motion.sample(at: time).angles, opacity: 0.6)
        }
    }

    private func drawArms(in context: GraphicsContext, shoulders: [CGPoint], arms: (upper: CGFloat, fore: CGFloat),
                          angles: ArmAngles, opacity: Double) {
        for (shoulder, other) in [(shoulders[0], shoulders[1]), (shoulders[1], shoulders[0])] {
            let arm = ArmMotion.place(shoulder: shoulder, otherShoulder: other, upperArm: arms.upper, forearm: arms.fore,
                                      angles: angles, forearmPlane: motion.forearmPlane)
            var path = Path()
            path.move(to: shoulder)
            path.addLine(to: arm.elbow)
            path.addLine(to: arm.wrist)
            context.stroke(path, with: .color(Self.ghostColor.opacity(opacity)),
                           style: StrokeStyle(lineWidth: max(8, arms.fore * 0.16), lineCap: .round, lineJoin: .round))
            var dumbbell = context
            dumbbell.opacity = opacity + 0.2
            DumbbellDrawing.draw(in: dumbbell, elbow: arm.elbow, wrist: arm.wrist, forearmLength: arms.fore)
        }
    }
}

/// The analyzer's own Start and Top thresholds as a short segment over each arm. The checkpoint the arm
/// is heading toward is bright, the other dim, and a segment turns solid once that arm reaches it.
struct RepThresholdOverlayView: View {
    let thresholds: [BodySide: ArmThresholds]
    let imageSize: CGSize

    var body: some View {
        Canvas { context, size in draw(in: context, size: size) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let fit = CoordinateConverter.aspectFitRect(for: imageSize, in: size)
        guard fit.width > 0 else { return }
        // Thresholds are unmirrored image pixels; the preview is a mirrored selfie.
        func display(_ point: CGPoint) -> CGPoint {
            CoordinateConverter.normalizedToContainer(
                normalized: CGPoint(x: 1 - point.x / imageSize.width, y: 1 - point.y / imageSize.height),
                imageSize: imageSize, containerSize: size)
        }
        var context = context
        context.clip(to: Path(fit))

        // Labels go on the segments furthest right on screen, at their outer end, clear of the body.
        let labeled = thresholds.max { lhs, rhs in
            display(lhs.value.startLine.from).x + display(lhs.value.startLine.to).x
                < display(rhs.value.startLine.from).x + display(rhs.value.startLine.to).x
        }?.key
        for (side, arm) in thresholds {
            for checkpoint in [RepCheckpoint.start, .top] {
                let line = arm.line(checkpoint)
                drawSegment(in: context, from: display(line.from), to: display(line.to), checkpoint: checkpoint, arm: arm,
                            label: side == labeled ? line.label : nil, fit: fit)
            }
        }
    }

    private func drawSegment(in context: GraphicsContext, from start: CGPoint, to end: CGPoint,
                             checkpoint: RepCheckpoint, arm: ArmThresholds, label: String?, fit: CGRect) {
        let color = checkpoint == .top ? WorkoutJointOverlayView.endPositionColor : WorkoutJointOverlayView.trackedColor
        let reached = arm.confirmed == checkpoint
        let isNext = arm.next == checkpoint
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        let style = reached
            ? StrokeStyle(lineWidth: 4, lineCap: .round)
            : StrokeStyle(lineWidth: isNext ? 3 : 2, lineCap: .round, dash: [10, 6])
        let opacity = reached || isNext ? 1 : 0.35
        context.stroke(path, with: .color(.black.opacity(0.5 * opacity)),
                       style: StrokeStyle(lineWidth: style.lineWidth + 2, lineCap: .round, dash: style.dash))
        context.stroke(path, with: .color(color.opacity(opacity)), style: style)
        guard let label else { return }
        let anchor = start.x > end.x ? start : end
        context.draw(Text(label).font(.caption.bold()).foregroundColor(color.opacity(opacity)),
                     at: CGPoint(x: min(anchor.x, fit.maxX - 4), y: anchor.y - 3), anchor: .bottomTrailing)
    }
}
