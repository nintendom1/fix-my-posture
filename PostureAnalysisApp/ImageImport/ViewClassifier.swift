import Foundation
import CoreGraphics

/// Classifier to estimate whether a photo is front view, left side, or right side view.
public struct ViewClassifier {

    public static func classify(pose: BodyPose, horizonContext: HorizonContext? = nil) -> PostureView {
        let classifiedPose: BodyPose
        classifiedPose = HorizonGeometry.leveledPose(pose, context: horizonContext)
        let landmarks = classifiedPose.landmarks

        // Extract bilateral pairs
        let leftShoulder = landmarks[.leftShoulder]
        let rightShoulder = landmarks[.rightShoulder]
        let leftHip = landmarks[.leftHip]
        let rightHip = landmarks[.rightHip]
        let leftEar = landmarks[.leftEar]
        let rightEar = landmarks[.rightEar]

        var bilateralCount = 0
        var totalWidthRatio: CGFloat = 0.0

        if let ls = leftShoulder, let rs = rightShoulder {
            let dx = abs(ls.normalizedLocation.x - rs.normalizedLocation.x)
            totalWidthRatio += dx
            bilateralCount += 1
        }

        if let lh = leftHip, let rh = rightHip {
            let dx = abs(lh.normalizedLocation.x - rh.normalizedLocation.x)
            totalWidthRatio += dx
            bilateralCount += 1
        }

        // Ear presence check for side view identification
        let hasLeftEar = (leftEar?.confidence ?? 0.0) > 0.3
        let hasRightEar = (rightEar?.confidence ?? 0.0) > 0.3

        if hasLeftEar && !hasRightEar {
            return .leftSide
        } else if hasRightEar && !hasLeftEar {
            return .rightSide
        }

        guard bilateralCount > 0 else {
            return .uncertain
        }

        let avgWidthRatio = totalWidthRatio / CGFloat(bilateralCount)

        // In front view, shoulder and hip horizontal distance is significant (> 0.12 of frame)
        if avgWidthRatio > 0.12 {
            return .front
        } else if avgWidthRatio < 0.06 {
            // Narrow horizontal distance indicates side profile
            if let earL = leftEar, let earR = rightEar {
                return earL.normalizedLocation.x < earR.normalizedLocation.x ? .leftSide : .rightSide
            }
            return .leftSide // Default side
        }

        return .uncertain
    }
}
