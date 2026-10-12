import CoreGraphics
import Foundation

/// Screen regions covered by a pose, in container points. Floating labels avoid these so they never
/// hide the body. Shared by the posture callouts and the workout tips.
public enum ProtectedBodyGeometry {
    public static func rects(pose: BodyPose, containerSize: CGSize) -> [CGRect] {
        let imageSize = CGSize(width: pose.imageWidth, height: pose.imageHeight)
        func point(_ type: LandmarkType) -> CGPoint? {
            pose[type].map { CoordinateConverter.normalizedToContainer(
                normalized: $0.normalizedLocation, imageSize: imageSize, containerSize: containerSize) }
        }
        var rects = pose.landmarks.keys.compactMap { type -> CGRect? in
            guard let p = point(type) else { return nil }
            let radius: CGFloat = [.nose, .leftEye, .rightEye, .leftEar, .rightEar].contains(type) ? 24 : 14
            return CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
        }
        for (a, b) in BodyPose.connections {
            guard let p1 = point(a), let p2 = point(b) else { continue }
            // Sampling follows the segment closely; an axis-aligned bounding box would
            // incorrectly reserve the empty corners around diagonal arms and legs.
            // Overlapping samples every <= 4 pt continuously cover the segment,
            // including diagonal gaps between the old three samples.
            let steps = max(1, Int(ceil(hypot(p2.x - p1.x, p2.y - p1.y) / 4)))
            for step in 0...steps {
                let progress = CGFloat(step) / CGFloat(steps)
                let sample = CGPoint(x: p1.x + (p2.x - p1.x) * progress,
                                     y: p1.y + (p2.y - p1.y) * progress)
                rects.append(CGRect(x: sample.x - 10, y: sample.y - 10, width: 20, height: 20))
            }
        }
        let torsoTypes: [LandmarkType] = [.leftShoulder, .rightShoulder, .leftHip, .rightHip, .root]
        let torsoPoints = torsoTypes.compactMap(point)
        if let first = torsoPoints.first {
            let torsoBounds = torsoPoints.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
                $0.union(CGRect(origin: $1, size: .zero))
            }
            rects.append(torsoBounds.insetBy(dx: -8, dy: -8))
        }
        return rects
    }
}
