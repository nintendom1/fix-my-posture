import Foundation
import CoreGraphics
import CoreVideo

/// Protocol for pose estimation engines.
public protocol PoseEstimator {
    /// Estimates full body pose from CGImage.
    func estimatePose(in image: CGImage) async throws -> BodyPose

    /// Estimates full body pose from CVPixelBuffer camera frame.
    func estimatePose(in pixelBuffer: CVPixelBuffer) async throws -> BodyPose
}
