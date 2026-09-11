import Foundation
import CoreGraphics
import CoreVideo

/// Protocol for pose estimation engines.
public protocol PoseEstimator {
    /// Estimates full body pose from CGImage.
    func estimatePose(in image: CGImage) async throws -> BodyPose

}

/// Synchronous frame processing runs on the capture queue, with late frames discarded.
/// Kept separate so still-photo estimators do not need camera-specific APIs.
public protocol FramePoseEstimator {
    /// Input is an upright, unmirrored camera frame.
    func estimatePose(in pixelBuffer: CVPixelBuffer) throws -> BodyPose
}
