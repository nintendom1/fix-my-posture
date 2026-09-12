import Foundation
import CoreGraphics
import UIKit

/// Utility for image center point rotation and horizon geometry transforms.
public enum HorizonGeometry {

    /// Maps a screen-space horizon into an unmirrored realtime camera buffer.
    public static func realtimeImageAngle(_ screenAngleDegrees: Double, isFrontCamera: Bool) -> Double {
        isFrontCamera ? -screenAngleDegrees : screenAngleDegrees
    }

    /// Maps a screen-space horizon through the same orientation/mirroring transform used
    /// when UIImage draws into its normalized upright representation.
    public static func capturedImageAngle(
        _ screenAngleDegrees: Double,
        isFrontCamera: Bool,
        orientation: UIImage.Orientation
    ) -> Double {
        let imageAngle = realtimeImageAngle(screenAngleDegrees, isFrontCamera: isFrontCamera)
        let radians = imageAngle * .pi / 180
        let a = CGPoint(x: 0.25, y: 0.5 - 0.25 * tan(radians))
        let b = CGPoint(x: 0.75, y: 0.5 + 0.25 * tan(radians))
        let mappedA = ImageNormalizer.mapNormalizedToOrientation(a, orientation: orientation, clampToImage: false)
        let mappedB = ImageNormalizer.mapNormalizedToOrientation(b, orientation: orientation, clampToImage: false)
        var result = atan2(mappedB.y - mappedA.y, mappedB.x - mappedA.x) * 180 / .pi
        // A horizon is an undirected line, so keep its equivalent representation
        // in the range used by posture geometry.
        while result > 90 { result -= 180 }
        while result < -90 { result += 180 }
        return abs(result) < 0.000_000_1 ? 0 : result
    }

    /// Returns geometry leveled to the persisted original-image horizon.
    public static func leveledPose(_ pose: BodyPose, context: HorizonContext?) -> BodyPose {
        guard let context, context.isCompensationApplied, context.angleDegrees != 0 else { return pose }
        return rotatePose(pose, angleDegrees: -context.angleDegrees)
    }

    /// Rotates a 2D point around image center in equal-scale pixel space.
    /// - Parameters:
    ///   - point: Input point in top-left origin image pixel space.
    ///   - imageWidth: Width of image in pixels.
    ///   - imageHeight: Height of image in pixels.
    ///   - angleDegrees: Rotation angle in degrees (positive angles rotate CCW in Cartesian / rising toward right).
    /// - Returns: Rotated point in image pixel space.
    public static func rotatePoint(
        _ point: CGPoint,
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        angleDegrees: Double
    ) -> CGPoint {
        guard angleDegrees != 0, imageWidth > 0, imageHeight > 0 else { return point }

        let centerX = imageWidth / 2.0
        let centerY = imageHeight / 2.0

        let dx = point.x - centerX
        let dy = point.y - centerY

        let radians = angleDegrees * (.pi / 180.0)
        let cosA = cos(radians)
        let sinA = sin(radians)

        // In image pixel space (top-left origin, +y down):
        let rotatedDx = dx * cosA + dy * sinA
        let rotatedDy = -dx * sinA + dy * cosA

        return CGPoint(
            x: centerX + rotatedDx,
            y: centerY + rotatedDy
        )
    }

    /// Rotates a landmark around image center and updates both pixel and normalized coordinates.
    public static func rotateLandmark(
        _ landmark: Landmark,
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        angleDegrees: Double
    ) -> Landmark {
        guard angleDegrees != 0, imageWidth > 0, imageHeight > 0 else { return landmark }

        let rotatedPixel = rotatePoint(
            landmark.imageLocation,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            angleDegrees: angleDegrees
        )

        // Recompute normalized location (bottom-left origin, 0.0-1.0) without clamping to bounds
        let normX = rotatedPixel.x / imageWidth
        let normY = 1.0 - (rotatedPixel.y / imageHeight)

        var result = landmark
        result.imageLocation = rotatedPixel
        result.normalizedLocation = CGPoint(x: normX, y: normY)
        return result
    }

    /// Rotates all landmarks in a pose around image center.
    public static func rotatePose(_ pose: BodyPose, angleDegrees: Double) -> BodyPose {
        guard angleDegrees != 0, pose.imageWidth > 0, pose.imageHeight > 0 else { return pose }

        var rotatedLandmarks: [LandmarkType: Landmark] = [:]
        for (type, lm) in pose.landmarks {
            rotatedLandmarks[type] = rotateLandmark(
                lm,
                imageWidth: pose.imageWidth,
                imageHeight: pose.imageHeight,
                angleDegrees: angleDegrees
            )
        }

        return BodyPose(
            landmarks: rotatedLandmarks,
            imageWidth: pose.imageWidth,
            imageHeight: pose.imageHeight
        )
    }
}
