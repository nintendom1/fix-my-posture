import Foundation
import CoreGraphics

/// Presentation only: always pass the original pose, before camera/display transforms.
public enum MeasurementPresentation {
    public static let convention = "Signed readings: + means toward your right in front view (your right side lower for level measurements), or forward in side view. − means the opposite. Readings without reliable direction remain unsigned. Knee angles, stance ratios and asymmetry magnitudes retain their original values. Colors indicate distance from the geometric reference: green within, amber outside, coral further outside; gray means unsupported. Hollow violet rings are personalized alignment targets."

    public static func isDirectional(_ id: MeasurementID) -> Bool {
        ![.kneeJointAngle, .kneeAnkleStanceRatio, .shoulderHeightAsymmetry, .hipHeightAsymmetry, .custom].contains(id)
    }

    public static func reading(_ measurement: PostureMeasurement, pose: BodyPose?, view: PostureView, horizonContext: HorizonContext? = nil) -> String {
        let digits = measurement.measurementID == .kneeAnkleStanceRatio ? 2 : 1
        let magnitude = abs(measurement.value)
        guard isDirectional(measurement.measurementID), let pose else {
            return String(format: "%.*f", digits, measurement.value == 0 ? 0 : measurement.value)
        }
        let targetPose = HorizonGeometry.leveledPose(pose, context: horizonContext)
        guard let direction = direction(measurement, pose: targetPose, view: view) else {
            return String(format: "%.*f", digits, measurement.value == 0 ? 0 : measurement.value)
        }
        let rounded = (magnitude * 10).rounded() / 10
        return (rounded == 0 ? "" : direction < 0 ? "−" : "+") + String(format: "%.1f", rounded)
    }

    private static func direction(_ measurement: PostureMeasurement, pose: BodyPose, view: PostureView) -> CGFloat? {
        func point(_ type: LandmarkType) -> CGPoint? {
            guard let landmark = pose[type], landmark.confidence >= 0.5,
                  landmark.imageLocation.x.isFinite, landmark.imageLocation.y.isFinite else { return nil }
            return landmark.imageLocation
        }
        func midpoint(_ a: LandmarkType, _ b: LandmarkType) -> CGPoint? {
            guard let a = point(a), let b = point(b) else { return nil }
            return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        let points = measurement.landmarksUsed.compactMap(point)
        guard points.count == measurement.landmarksUsed.count, !points.isEmpty else { return nil }
        if view == .front {
            switch measurement.measurementID {
            case .headTiltAngle, .shoulderLineAngle, .hipLineAngle:
                guard points.count == 2 else { return nil }
                return points[1].y - points[0].y
            case .torsoLateralDeviation, .bodyCenterlineDeviation:
                guard let left = point(.leftShoulder) ?? point(.leftHip),
                      let right = point(.rightShoulder) ?? point(.rightHip), abs(right.x - left.x) > 1 else { return nil }
                let top = measurement.measurementID == .torsoLateralDeviation ? point(.neck) : point(.nose)
                let base = measurement.measurementID == .torsoLateralDeviation ? midpoint(.leftHip, .rightHip) : midpoint(.leftAnkle, .rightAnkle)
                guard let top, let base else { return nil }
                return (top.x - base.x) * (right.x - left.x)
            default: return nil
            }
        }
        guard view == .leftSide || view == .rightSide, points.count == 2 else { return nil }
        let ear = view == .leftSide ? point(.leftEar) : point(.rightEar)
        let face = point(.nose) ?? (view == .leftSide ? point(.leftEye) : point(.rightEye))
        guard let ear, let face, abs(face.x - ear.x) > max(2, pose.imageWidth * 0.005) else { return nil }
        return (points[0].x - points[1].x) * (face.x - ear.x)
    }

    public static func explanation(_ measurement: PostureMeasurement) -> String {
        // Legacy explanations sometimes use image-relative left/right; avoid contradictory directions.
        isDirectional(measurement.measurementID)
            ? "Geometric deviation from the reference. See the sign convention above; readings without reliable direction remain unsigned."
            : measurement.explanation
    }

    public static func jointFeedback(measurements: [PostureMeasurement], pose: BodyPose, view: PostureView,
                                     profile: PostureReferenceProfile) -> [LandmarkType: MeasurementFeedback] {
        var result: [LandmarkType: MeasurementFeedback] = [:]
        for measurement in measurements {
            let feedback = MeasurementFeedbackEvaluator().feedback(for: measurement, view: view, profile: profile)
            guard !feedback.isLowConfidence, feedback.severity != .unavailable,
                  measurement.landmarksUsed.allSatisfy({ (pose[$0]?.confidence ?? 0) >= 0.5 }) else { continue }
            for joint in measurement.landmarksUsed where result[joint] == nil || result[joint]!.severity < feedback.severity {
                result[joint] = feedback
            }
        }
        return result
    }
}
