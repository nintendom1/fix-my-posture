import CoreGraphics
import Foundation

/// The space an exercise's arms and weights sweep through, in arm lengths (upper arm + forearm)
/// from the shoulders. Tips stay out of it for the whole set, not just where the arms are right now.
struct MotionEnvelope: Equatable {
    /// Above the higher shoulder.
    var above: CGFloat
    /// Below the lower shoulder.
    var below: CGFloat
    /// Beyond each shoulder, away from the body.
    var outward: CGFloat

    /// In y-down container points.
    func rect(leftShoulder: CGPoint, rightShoulder: CGPoint, armLength: CGFloat) -> CGRect {
        let minX = min(leftShoulder.x, rightShoulder.x) - outward * armLength
        let maxX = max(leftShoulder.x, rightShoulder.x) + outward * armLength
        let minY = min(leftShoulder.y, rightShoulder.y) - above * armLength
        let maxY = max(leftShoulder.y, rightShoulder.y) + below * armLength
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Where a coaching tip goes: clear of the body, the exercise's motion envelope, and the HUD.
/// Pure geometry in the workout overlay coordinate space.
enum WorkoutTipLayout {
    /// Clearance from the screen edges, the body, and the HUD.
    static let margin: CGFloat = 8
    /// Distance from a HUD region to a tip placed beside it.
    static let hudGap: CGFloat = 12

    /// Keeps `previous` while it is still valid for this size; otherwise takes the first valid candidate:
    /// below the top HUD (center, left, right), above the bottom HUD (center, left, right), then the left
    /// and right gutters. Nil means there's no room, so the cue is only spoken.
    static func placement(size: CGSize, container: CGRect, protected: [CGRect], reserved: [CGRect],
                          previous: CGRect?) -> CGRect? {
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else { return nil }
        let bounds = container.insetBy(dx: margin, dy: margin)
        let blocked = (protected + reserved).map { $0.insetBy(dx: -margin, dy: -margin) }
        func fits(_ frame: CGRect) -> Bool {
            bounds.contains(frame) && !blocked.contains { $0.intersects(frame) }
        }
        if let previous, matches(previous.size, size), fits(previous) {
            return previous
        }
        return candidates(size: size, container: container, reserved: reserved).first(where: fits)
    }

    /// Tries each size in order, for example one line and then a narrower wrapped tip. A tip already on
    /// screen keeps its slot and shape while they stay valid.
    static func placement(sizes: [CGSize], container: CGRect, protected: [CGRect], reserved: [CGRect],
                          previous: CGRect?) -> CGRect? {
        if let previous, let size = sizes.first(where: { matches($0, previous.size) }),
           placement(size: size, container: container, protected: protected, reserved: reserved,
                     previous: previous) == previous {
            return previous
        }
        for size in sizes {
            if let frame = placement(size: size, container: container, protected: protected,
                                     reserved: reserved, previous: nil) {
                return frame
            }
        }
        return nil
    }

    /// Candidate frames in preference order. The top HUD is the reserved region nearest the top edge,
    /// the bottom HUD the one nearest the bottom; without them the container edges stand in.
    /// Gutters are tried from the middle of the space between the HUDs outward, alternating below and
    /// above, because beside the hips is often free when the arms' envelope fills chest height.
    static func candidates(size: CGSize, container: CGRect, reserved: [CGRect]) -> [CGRect] {
        let top = reserved.filter { $0.midY < container.midY }.map(\.maxY).max() ?? container.minY
        let bottom = reserved.filter { $0.midY >= container.midY }.map(\.minY).min() ?? container.maxY
        let left = container.minX + margin
        let right = container.maxX - margin - size.width
        let center = container.midX - size.width / 2
        let belowTop = top + hudGap
        let aboveBottom = bottom - hudGap - size.height
        var positions: [(CGFloat, CGFloat)] = [
            (center, belowTop), (left, belowTop), (right, belowTop),
            (center, aboveBottom), (left, aboveBottom), (right, aboveBottom)
        ]
        let middle = (top + bottom) / 2 - size.height / 2
        let reach = max(0, (bottom - top) / 2)
        for offset in stride(from: CGFloat(0), through: reach, by: gutterStep) {
            for y in offset == 0 ? [middle] : [middle + offset, middle - offset] {
                positions += [(left, y), (right, y)]
            }
        }
        return positions.map { CGRect(x: $0.0, y: $0.1, width: size.width, height: size.height) }
    }

    /// Vertical step between gutter candidates.
    static let gutterStep: CGFloat = 24

    /// The body (every visible joint and segment) plus the exercise's motion envelope, in container points.
    static func protectedRects(pose: BodyPose?, envelope: CGRect?, containerSize: CGSize) -> [CGRect] {
        let body = pose.map { ProtectedBodyGeometry.rects(pose: $0, containerSize: containerSize) } ?? []
        return body + (envelope.map { [$0] } ?? [])
    }

    /// The envelope around the user's smoothed shoulders, scaled by their measured arm length. Typical
    /// proportions stand in until the arms are measured.
    static func envelopeRect(_ envelope: MotionEnvelope, overlay: WorkoutOverlayState, metrics: GuideMetrics?,
                             containerSize: CGSize) -> CGRect? {
        let imageSize = overlay.imageSize
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        let fit = CoordinateConverter.aspectFitRect(for: imageSize, in: containerSize)
        guard fit.width > 0 else { return nil }
        // From the side only one shoulder may be tracked; the envelope then surrounds it.
        var shoulders = [overlay.joints[.leftShoulder], overlay.joints[.rightShoulder]]
            .compactMap { $0 }.filter { !$0.isStale }.map {
                CoordinateConverter.normalizedToContainer(normalized: $0.location, imageSize: imageSize, containerSize: containerSize)
            }
        guard let first = shoulders.first else { return nil }
        if shoulders.count == 1 { shoulders.append(first) }
        let armLength: CGFloat
        if let metrics {
            armLength = (metrics.upperArm + metrics.forearm) * fit.width / imageSize.width
        } else {
            let shoulderWidth = abs(shoulders[0].x - shoulders[1].x)
            armLength = shoulderWidth * (GuideMetrics.upperArmToShoulderWidth + GuideMetrics.forearmToShoulderWidth)
        }
        return envelope.rect(leftShoulder: shoulders[0], rightShoulder: shoulders[1], armLength: armLength)
    }

    private static func matches(_ a: CGSize, _ b: CGSize) -> Bool {
        abs(a.width - b.width) <= 1 && abs(a.height - b.height) <= 1
    }
}
