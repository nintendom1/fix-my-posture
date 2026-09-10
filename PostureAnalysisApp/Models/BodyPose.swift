import Foundation
import CoreGraphics

/// Model representing a full body pose with joint landmarks.
public struct BodyPose: Codable, Hashable {
    /// Map of landmark types to Landmark objects.
    public var landmarks: [LandmarkType: Landmark]

    /// Image width in pixels.
    public var imageWidth: CGFloat

    /// Image height in pixels.
    public var imageHeight: CGFloat

    /// Mean confidence across all detected landmarks.
    public var averageConfidence: Double {
        guard !landmarks.isEmpty else { return 0.0 }
        let total = landmarks.values.reduce(0.0) { $0 + $1.confidence }
        return total / Double(landmarks.count)
    }

    public init(landmarks: [LandmarkType: Landmark], imageWidth: CGFloat, imageHeight: CGFloat) {
        self.landmarks = landmarks
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }

    public subscript(type: LandmarkType) -> Landmark? {
        get { landmarks[type] }
        set { landmarks[type] = newValue }
    }

    /// Skeleton joint connection pairs for drawing visualization lines.
    public static let connections: [(LandmarkType, LandmarkType)] = [
        // Head / Face
        (.leftEar, .leftEye),
        (.leftEye, .nose),
        (.nose, .rightEye),
        (.rightEye, .rightEar),
        (.nose, .neck),

        // Torso / Shoulders
        (.leftShoulder, .neck),
        (.neck, .rightShoulder),
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .root),
        (.rightHip, .root),
        (.neck, .root),

        // Arms
        (.leftShoulder, .leftElbow),
        (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist),

        // Legs
        (.leftHip, .leftKnee),
        (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee),
        (.rightKnee, .rightAnkle)
    ]
}
