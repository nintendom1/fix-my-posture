import SwiftUI

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
