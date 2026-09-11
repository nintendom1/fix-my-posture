import UIKit
import CoreGraphics

/// Utility for normalizing UIImage orientations to `.up` and mapping coordinates between orientations.
public struct ImageNormalizer {

    /// Re-renders a `UIImage` into an upright (`.up`) orientation graphics context.
    /// Returns an upright `UIImage` whose bitmap pixel dimensions match its `.up` layout size.
    public static func normalizeToUpright(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up {
            return image
        }

        let size = image.size
        guard size.width > 0 && size.height > 0 else { return image }

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let normalizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }

        return normalizedImage
    }

    /// Maps a normalized coordinate (Vision space: origin at bottom-left, x: [0,1], y: [0,1])
    /// from standard `.up` frame to match a target `UIImage.Orientation`.
    public static func mapNormalizedToOrientation(
        _ point: CGPoint,
        orientation: UIImage.Orientation
    ) -> CGPoint {
        var x = point.x
        var y = point.y

        switch orientation {
        case .up:
            break
        case .upMirrored:
            x = 1.0 - x
        case .down:
            x = 1.0 - x
            y = 1.0 - y
        case .downMirrored:
            y = 1.0 - y
        case .left:
            let temp = x
            x = 1.0 - y
            y = temp
        case .leftMirrored:
            let temp = x
            x = 1.0 - y
            y = 1.0 - temp
        case .right:
            let temp = x
            x = y
            y = 1.0 - temp
        case .rightMirrored:
            let temp = x
            x = y
            y = temp
        @unknown default:
            break
        }

        return CGPoint(
            x: max(0.0, min(1.0, x)),
            y: max(0.0, min(1.0, y))
        )
    }

    /// Maps all landmark locations in a `BodyPose` to fit a target `UIImage.Orientation` display frame without modifying underlying measurements.
    public static func mapPoseToOrientation(
        _ pose: BodyPose,
        orientation: UIImage.Orientation
    ) -> BodyPose {
        guard orientation != .up else { return pose }

        var isSwappedDimensions = false
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            isSwappedDimensions = true
        default:
            isSwappedDimensions = false
        }

        let newWidth = isSwappedDimensions ? pose.imageHeight : pose.imageWidth
        let newHeight = isSwappedDimensions ? pose.imageWidth : pose.imageHeight

        var mappedLandmarks: [LandmarkType: Landmark] = [:]
        for (type, lm) in pose.landmarks {
            let mappedNorm = mapNormalizedToOrientation(lm.normalizedLocation, orientation: orientation)
            let mappedImg = CoordinateConverter.normalizedToImagePixel(
                normalized: mappedNorm,
                imageWidth: newWidth,
                imageHeight: newHeight
            )

            mappedLandmarks[type] = Landmark(
                type: type,
                normalizedLocation: mappedNorm,
                imageLocation: mappedImg,
                confidence: lm.confidence,
                isManuallyCorrected: lm.isManuallyCorrected
            )
        }

        return BodyPose(landmarks: mappedLandmarks, imageWidth: newWidth, imageHeight: newHeight)
    }
}
