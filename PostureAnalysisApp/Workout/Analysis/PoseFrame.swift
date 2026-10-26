import CoreGraphics
import Foundation

/// One pose sample from the workout camera.
/// Landmarks below the live confidence floor are already removed, and geometry is unmirrored image pixels.
struct PoseFrame {
    var pose: BodyPose
    /// Sample buffer presentation time in seconds. Compare only with other frame timestamps.
    let timestamp: TimeInterval
    /// Joints placed past the frame edge by `OffscreenJointEstimator` rather than seen.
    var estimatedJoints: Set<LandmarkType> = []
    /// Capture order of accepted camera samples; a gap means a frame was dropped before analysis. Nil in tests.
    var sequence: Int? = nil
    /// How long this frame waited between pose estimation and reaching the coach, measured by the camera on the
    /// uptime clock as it handed the frame over; a main-thread stall makes it long. 0 in tests. The coach places
    /// the frame at now − delay.
    var deliveryDelay: TimeInterval = 0
    /// Joints below the live confidence floor, kept only for session recordings. Analysis never reads them.
    var lowConfidenceLandmarks: [LandmarkType: Landmark] = [:]

    var imageSize: CGSize { CGSize(width: pose.imageWidth, height: pose.imageHeight) }

    /// Pixel location (origin top-left) when the joint meets `minimumConfidence`.
    func point(_ type: LandmarkType, minimumConfidence: Double) -> CGPoint? {
        guard let landmark = pose[type], landmark.confidence >= minimumConfidence else { return nil }
        return landmark.imageLocation
    }
}
