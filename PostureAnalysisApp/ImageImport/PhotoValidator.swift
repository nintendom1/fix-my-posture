import Foundation
import CoreGraphics

/// Validation utility to check standing photo quality and landmark visibility before posture analysis.
public struct PhotoValidator {

    public struct ValidationResult {
        public let isValidForAnalysis: Bool
        public let warnings: [String]
    }

    public static func validate(pose: BodyPose, metadata: ImageMetadata) -> ValidationResult {
        var warnings: [String] = []

        let landmarks = pose.landmarks

        // 1. Minimum total landmarks count
        if landmarks.count < 6 {
            warnings.append("Fewer than 6 body landmarks were detected. Please ensure full body is illuminated and visible.")
        }

        // 2. Check for key landmarks presence
        let keyLandmarks: [LandmarkType] = [.neck, .leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftAnkle, .rightAnkle]
        let missingKey = keyLandmarks.filter { landmarks[$0] == nil }
        if !missingKey.isEmpty {
            let names = missingKey.map { $0.displayName }.joined(separator: ", ")
            warnings.append("Missing key body landmarks: \(names). Posture calculations may be reduced in precision.")
        }

        // 3. Low confidence check
        let lowConfLandmarks = landmarks.values.filter { $0.confidence < 0.3 }
        if !lowConfLandmarks.isEmpty {
            warnings.append("\(lowConfLandmarks.count) landmark(s) have low detection confidence. You can manually adjust them in Edit Landmarks mode.")
        }

        // 4. Head / Feet Cropping check (near image borders)
        let edgeThreshold: CGFloat = 0.02
        if let headLandmark = landmarks[.nose] ?? landmarks[.leftEye] ?? landmarks[.rightEye] ?? landmarks[.neck] {
            if headLandmark.normalizedLocation.y > (1.0 - edgeThreshold) {
                warnings.append("Head appears close to the top frame boundary. Ensure full body fits inside the frame.")
            }
        }

        if let leftAnkle = landmarks[.leftAnkle], leftAnkle.normalizedLocation.y < edgeThreshold {
            warnings.append("Feet appear cropped at the bottom edge.")
        } else if let rightAnkle = landmarks[.rightAnkle], rightAnkle.normalizedLocation.y < edgeThreshold {
            warnings.append("Feet appear cropped at the bottom edge.")
        }

        // 5. Subject size check (height spanning percentage of frame)
        let yValues = landmarks.values.map { $0.normalizedLocation.y }
        if let minY = yValues.min(), let maxY = yValues.max() {
            let verticalSpan = maxY - minY
            if verticalSpan < 0.45 {
                warnings.append("Person occupies less than 45% of vertical frame height. Stand closer to the camera for optimal accuracy.")
            }
        }

        return ValidationResult(isValidForAnalysis: true, warnings: warnings)
    }
}
