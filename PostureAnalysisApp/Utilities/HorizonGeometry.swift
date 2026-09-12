import Foundation
import CoreGraphics
import UIKit

/// Utility for image center point rotation and horizon geometry transforms.
public enum HorizonGeometry {

    /// Transforms a device roll reading through captured UIImage.Orientation into upright pixel space.
    public static func transformAngleForOrientation(_ angleDegrees: Double, orientation: UIImage.Orientation) -> Double {
        switch orientation {
        case .up, .upMirrored:
            return angleDegrees
        case .down, .downMirrored:
            return -angleDegrees
        case .left, .leftMirrored:
            return angleDegrees
        case .right, .rightMirrored:
            return angleDegrees
        @unknown default:
            return angleDegrees
        }
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
