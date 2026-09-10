import Foundation
import CoreGraphics
import Vision

/// Apple Vision pose estimator conforming to `PoseEstimator`.
public final class AppleVisionPoseEstimator: PoseEstimator {

    public init() {}

    /// Estimates body pose landmarks in the provided CGImage using `VNDetectHumanBodyPoseRequest`.
    public func estimatePose(in image: CGImage) async throws -> BodyPose {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)

        let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNDetectHumanBodyPoseRequest()

        try requestHandler.perform([request])

        guard let observations = request.results, let primaryObservation = observations.first else {
            return BodyPose(landmarks: [:], imageWidth: width, imageHeight: height)
        }

        var landmarks: [LandmarkType: Landmark] = [:]

        // Map Vision joint names to our domain LandmarkType
        let jointMapping: [(VNHumanBodyPoseObservation.JointName, LandmarkType)] = [
            (.nose, .nose),
            (.neck, .neck),
            (.leftEye, .leftEye),
            (.rightEye, .rightEye),
            (.leftEar, .leftEar),
            (.rightEar, .rightEar),
            (.leftShoulder, .leftShoulder),
            (.rightShoulder, .rightShoulder),
            (.leftElbow, .leftElbow),
            (.rightElbow, .rightElbow),
            (.leftWrist, .leftWrist),
            (.rightWrist, .rightWrist),
            (.root, .root),
            (.leftHip, .leftHip),
            (.rightHip, .rightHip),
            (.leftKnee, .leftKnee),
            (.rightKnee, .rightKnee),
            (.leftAnkle, .leftAnkle),
            (.rightAnkle, .rightAnkle)
        ]

        for (visionJoint, landmarkType) in jointMapping {
            do {
                let recognizedPoint = try primaryObservation.recognizedPoint(visionJoint)
                if recognizedPoint.confidence > 0.01 {
                    // Vision normalized coordinates have origin (0,0) at bottom-left.
                    let normX = recognizedPoint.location.x
                    let normY = recognizedPoint.location.y

                    // Image pixel coordinate with origin top-left:
                    let imgX = normX * width
                    let imgY = (1.0 - normY) * height

                    let landmark = Landmark(
                        type: landmarkType,
                        normalizedLocation: CGPoint(x: normX, y: normY),
                        imageLocation: CGPoint(x: imgX, y: imgY),
                        confidence: Double(recognizedPoint.confidence),
                        isManuallyCorrected: false
                    )
                    landmarks[landmarkType] = landmark
                }
            } catch {
                // Joint not recognized or unsupported
                continue
            }
        }

        return BodyPose(landmarks: landmarks, imageWidth: width, imageHeight: height)
    }
}
