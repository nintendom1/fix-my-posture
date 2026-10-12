import SwiftUI

/// Draws only the exercise's focus joints and segments over the mirrored preview.
struct WorkoutJointOverlayView: View {
    let overlay: WorkoutOverlayState

    static let trackedColor = Color.cyan
    static let endPositionColor = Color(red: 0.31, green: 0.87, blue: 0.64)
    static let staleColor = Color.gray.opacity(0.7)
    static let referenceColor = Color.white.opacity(0.45)
    /// Joints a corrective tip refers to. Amber draws attention without signaling danger; never red.
    static let cueColor = Color(red: 1, green: 0.76, blue: 0.24)
    static let jointRadius: CGFloat = 7
    static let limbWidth: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            guard overlay.imageSize.width > 0, overlay.imageSize.height > 0 else { return }
            func point(_ joint: OverlayJoint) -> CGPoint {
                CoordinateConverter.normalizedToContainer(normalized: joint.location, imageSize: overlay.imageSize, containerSize: size)
            }

            for segment in overlay.segments {
                guard let from = overlay.joints[segment.from], let to = overlay.joints[segment.to] else { continue }
                var path = Path()
                path.move(to: point(from))
                path.addLine(to: point(to))
                let color: Color
                let emphasized = overlay.emphasizedJoints.contains(segment.from) && overlay.emphasizedJoints.contains(segment.to)
                if from.isStale || to.isStale {
                    color = Self.staleColor
                } else if emphasized {
                    color = Self.cueColor
                } else if segment.style == .reference {
                    color = Self.referenceColor
                } else {
                    color = isAtEndPosition(segment.from) && isAtEndPosition(segment.to) ? Self.endPositionColor : Self.trackedColor
                }
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: segment.style == .limb ? Self.limbWidth : 2, lineCap: .round))
            }

            for (type, joint) in overlay.joints {
                let center = point(joint)
                let radius = Self.jointRadius
                let circle = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                context.fill(circle, with: .color(color(for: type, joint: joint)))
                context.stroke(circle, with: .color(.white), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func isAtEndPosition(_ joint: LandmarkType) -> Bool {
        guard let side = BodySide.side(of: joint), side.armJoints.contains(joint) else { return false }
        return overlay.endPositionSides.contains(side)
    }

    private func color(for type: LandmarkType, joint: OverlayJoint) -> Color {
        if joint.isStale { return Self.staleColor }
        if overlay.emphasizedJoints.contains(type) { return Self.cueColor }
        return isAtEndPosition(type) ? Self.endPositionColor : Self.trackedColor
    }
}
