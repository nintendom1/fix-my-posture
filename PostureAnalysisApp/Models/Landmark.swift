import Foundation
import CoreGraphics

/// Represents a single detected or corrected body landmark.
public struct Landmark: Codable, Hashable, Identifiable {
    public var id: LandmarkType { type }

    /// Type of the joint landmark.
    public let type: LandmarkType

    /// Normalized coordinate (x: [0..1], y: [0..1] where (0,0) is bottom-left or top-left depending on coordinate system).
    /// Standard Vision normalized coords have origin (0,0) at bottom-left.
    public var normalizedLocation: CGPoint

    /// Image coordinate in pixels corresponding to the original image dimensions.
    public var imageLocation: CGPoint

    /// Estimation confidence from Vision or ML model [0.0..1.0].
    public var confidence: Double

    /// Indicates whether this landmark was manually moved/corrected by the user.
    public var isManuallyCorrected: Bool

    // Hash coordinate components explicitly for SDKs where CGPoint is not Hashable.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(normalizedLocation.x)
        hasher.combine(normalizedLocation.y)
        hasher.combine(imageLocation.x)
        hasher.combine(imageLocation.y)
        hasher.combine(confidence)
        hasher.combine(isManuallyCorrected)
    }

    public init(
        type: LandmarkType,
        normalizedLocation: CGPoint,
        imageLocation: CGPoint,
        confidence: Double,
        isManuallyCorrected: Bool = false
    ) {
        self.type = type
        self.normalizedLocation = normalizedLocation
        self.imageLocation = imageLocation
        self.confidence = confidence
        self.isManuallyCorrected = isManuallyCorrected
    }
}
