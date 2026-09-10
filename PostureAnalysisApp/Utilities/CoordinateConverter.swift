import Foundation
import CoreGraphics

/// Utility for aspect-ratio transformation and coordinate system mapping between normalized, pixel, and SwiftUI frame coordinates.
public struct CoordinateConverter {

    /// Converts a normalized coordinate (Vision space: origin at bottom-left, x: [0,1], y: [0,1])
    /// to pixel coordinates in image space (origin at top-left, x: [0, width], y: [0, height]).
    public static func normalizedToImagePixel(normalized: CGPoint, imageWidth: CGFloat, imageHeight: CGFloat) -> CGPoint {
        CGPoint(
            x: normalized.x * imageWidth,
            y: (1.0 - normalized.y) * imageHeight
        )
    }

    /// Converts an image pixel coordinate (origin at top-left) back to normalized coordinate (Vision space: origin at bottom-left).
    public static func imagePixelToNormalized(pixel: CGPoint, imageWidth: CGFloat, imageHeight: CGFloat) -> CGPoint {
        guard imageWidth > 0 && imageHeight > 0 else { return .zero }
        return CGPoint(
            x: max(0.0, min(1.0, pixel.x / imageWidth)),
            y: max(0.0, min(1.0, 1.0 - (pixel.y / imageHeight)))
        )
    }

    /// Calculates the actual rendered image rectangle inside a container view with `.aspectRatio(contentMode: .fit)`.
    public static func aspectFitRect(for imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0 && imageSize.height > 0 && containerSize.width > 0 && containerSize.height > 0 else {
            return .zero
        }

        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        var renderSize = containerSize
        if imageAspect > containerAspect {
            renderSize.height = containerSize.width / imageAspect
        } else {
            renderSize.width = containerSize.height * imageAspect
        }

        let originX = (containerSize.width - renderSize.width) / 2.0
        let originY = (containerSize.height - renderSize.height) / 2.0

        return CGRect(origin: CGPoint(x: originX, y: originY), size: renderSize)
    }

    /// Maps a normalized Vision coordinate (origin bottom-left) to container view coordinates accounting for aspect-fit letterboxing.
    public static func normalizedToContainer(normalized: CGPoint, imageSize: CGSize, containerSize: CGSize) -> CGPoint {
        let fitRect = aspectFitRect(for: imageSize, in: containerSize)
        guard fitRect.width > 0 && fitRect.height > 0 else { return .zero }

        let localX = normalized.x * fitRect.width
        let localY = (1.0 - normalized.y) * fitRect.height

        return CGPoint(
            x: fitRect.origin.x + localX,
            y: fitRect.origin.y + localY
        )
    }

    /// Maps a container touch point to normalized Vision coordinates (origin bottom-left).
    public static func containerToNormalized(touchPoint: CGPoint, imageSize: CGSize, containerSize: CGSize) -> CGPoint {
        let fitRect = aspectFitRect(for: imageSize, in: containerSize)
        guard fitRect.width > 0 && fitRect.height > 0 else { return .zero }

        let localX = touchPoint.x - fitRect.origin.x
        let localY = touchPoint.y - fitRect.origin.y

        let normX = max(0.0, min(1.0, localX / fitRect.width))
        let normY = max(0.0, min(1.0, 1.0 - (localY / fitRect.height)))

        return CGPoint(x: normX, y: normY)
    }
}
