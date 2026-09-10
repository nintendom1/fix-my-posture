import Foundation
import CoreGraphics

/// Protocol for pose estimation engines.
public protocol PoseEstimator {
    /// Estimates full body pose from CGImage.
    func estimatePose(in image: CGImage) async throws -> BodyPose
}
