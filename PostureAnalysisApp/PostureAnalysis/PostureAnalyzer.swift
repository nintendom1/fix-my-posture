import Foundation
import CoreGraphics

/// Posture measurement engine calculating explainable geometric metrics.
public struct PostureAnalyzer {

    public init() {}

    /// Analyzes the body pose based on specified view angle.
    public func analyze(
        pose: BodyPose,
        imageMetadata: ImageMetadata,
        view: PostureView
    ) -> PostureAssessment {
        var measurements: [PostureMeasurement] = []

        switch view {
        case .front:
            measurements = analyzeFrontView(pose: pose)
        case .leftSide, .rightSide:
            measurements = analyzeSideView(pose: pose, side: view)
        case .uncertain:
            measurements = analyzeFrontView(pose: pose) + analyzeSideView(pose: pose, side: view)
        }

        let validation = PhotoValidator.validate(pose: pose, metadata: imageMetadata)

        return PostureAssessment(
            id: UUID(),
            date: Date(),
            imageRelativePath: "",
            view: view,
            pose: pose,
            measurements: measurements,
            warnings: validation.warnings,
            isBaseline: false,
            appVersion: "1.0.0"
        )
    }

    // MARK: - Front View Geometry

    private func analyzeFrontView(pose: BodyPose) -> [PostureMeasurement] {
        var results: [PostureMeasurement] = []

        // 1. Head Tilt (Angle between eye line or ear line and horizontal in pixel space)
        if let p1 = pose[.leftEye] ?? pose[.leftEar],
           let p2 = pose[.rightEye] ?? pose[.rightEar] {
            let angle = angleWithHorizontalDegrees(p1: p1.imageLocation, p2: p2.imageLocation)
            let conf = min(p1.confidence, p2.confidence)
            let dir = angle > 0 ? "tilted right" : "tilted left"
            results.append(PostureMeasurement(
                id: .headTiltAngle,
                name: "Head Tilt Angle",
                value: roundToDecimal(abs(angle), 1),
                unit: "°",
                landmarksUsed: [p1.type, p2.type],
                confidence: conf,
                explanation: "Head tilt is \(roundToDecimal(abs(angle), 1))° (\(dir)) relative to horizontal baseline."
            ))
        }

        // 2. Shoulder Line Angle & Height Asymmetry
        if let ls = pose[.leftShoulder], let rs = pose[.rightShoulder] {
            let angle = angleWithHorizontalDegrees(p1: ls.imageLocation, p2: rs.imageLocation)
            let dyPixel = abs(ls.imageLocation.y - rs.imageLocation.y)
            let dyPercent = (dyPixel / pose.imageHeight) * 100.0
            let higherSide = ls.imageLocation.y < rs.imageLocation.y ? "Left" : "Right" // pixel Y=0 is top
            let conf = min(ls.confidence, rs.confidence)

            results.append(PostureMeasurement(
                id: .shoulderLineAngle,
                name: "Shoulder Line Angle",
                value: roundToDecimal(abs(angle), 1),
                unit: "°",
                landmarksUsed: [.leftShoulder, .rightShoulder],
                confidence: conf,
                explanation: "Shoulder line angle is \(roundToDecimal(abs(angle), 1))° from horizontal. \(higherSide) shoulder is positioned higher."
            ))

            results.append(PostureMeasurement(
                id: .shoulderHeightAsymmetry,
                name: "Shoulder Height Asymmetry",
                value: roundToDecimal(dyPercent, 1),
                unit: "% height",
                landmarksUsed: [.leftShoulder, .rightShoulder],
                confidence: conf,
                explanation: "Vertical shoulder level difference is \(roundToDecimal(dyPercent, 1))% of image height."
            ))
        }

        // 3. Hip Line Angle & Height Asymmetry
        if let lh = pose[.leftHip], let rh = pose[.rightHip] {
            let angle = angleWithHorizontalDegrees(p1: lh.imageLocation, p2: rh.imageLocation)
            let dyPixel = abs(lh.imageLocation.y - rh.imageLocation.y)
            let dyPercent = (dyPixel / pose.imageHeight) * 100.0
            let higherSide = lh.imageLocation.y < rh.imageLocation.y ? "Left" : "Right"
            let conf = min(lh.confidence, rh.confidence)

            results.append(PostureMeasurement(
                id: .hipLineAngle,
                name: "Hip Line Angle",
                value: roundToDecimal(abs(angle), 1),
                unit: "°",
                landmarksUsed: [.leftHip, .rightHip],
                confidence: conf,
                explanation: "Pelvic hip line angle is \(roundToDecimal(abs(angle), 1))° relative to horizontal. \(higherSide) hip is positioned higher."
            ))

            results.append(PostureMeasurement(
                id: .hipHeightAsymmetry,
                name: "Hip Height Asymmetry",
                value: roundToDecimal(dyPercent, 1),
                unit: "% height",
                landmarksUsed: [.leftHip, .rightHip],
                confidence: conf,
                explanation: "Vertical hip level asymmetry is \(roundToDecimal(dyPercent, 1))% of image height."
            ))
        }

        // 4. Torso Lateral Deviation (Neck center to Hip center relative to vertical in pixel space)
        if let neck = pose[.neck],
           let lh = pose[.leftHip], let rh = pose[.rightHip] {
            let hipCenter = CGPoint(
                x: (lh.imageLocation.x + rh.imageLocation.x) / 2.0,
                y: (lh.imageLocation.y + rh.imageLocation.y) / 2.0
            )
            let angle = angleWithVerticalDegrees(p1: neck.imageLocation, p2: hipCenter)
            let dir = neck.imageLocation.x > hipCenter.x ? "right" : "left"
            let conf = min(neck.confidence, lh.confidence, rh.confidence)

            results.append(PostureMeasurement(
                id: .torsoLateralDeviation,
                name: "Torso Lateral Deviation",
                value: roundToDecimal(abs(angle), 1),
                unit: "°",
                landmarksUsed: [.neck, .leftHip, .rightHip],
                confidence: conf,
                explanation: "Upper torso leans \(roundToDecimal(abs(angle), 1))° to the \(dir) relative to pelvic midpoint."
            ))
        }

        // 5. Stance & Knee Alignment Asymmetry
        if let lKnee = pose[.leftKnee], let rKnee = pose[.rightKnee],
           let lAnkle = pose[.leftAnkle], let rAnkle = pose[.rightAnkle] {
            let kneeDist = abs(lKnee.imageLocation.x - rKnee.imageLocation.x)
            let ankleDist = abs(lAnkle.imageLocation.x - rAnkle.imageLocation.x)
            let ratio = ankleDist > 0 ? (kneeDist / ankleDist) : 1.0
            let conf = min(lKnee.confidence, rKnee.confidence, lAnkle.confidence, rAnkle.confidence)

            results.append(PostureMeasurement(
                id: .kneeAnkleStanceRatio,
                name: "Knee-to-Ankle Stance Ratio",
                value: roundToDecimal(ratio, 2),
                unit: "ratio",
                landmarksUsed: [.leftKnee, .rightKnee, .leftAnkle, .rightAnkle],
                confidence: conf,
                explanation: "Ratio of knee width to ankle width is \(roundToDecimal(ratio, 2)). Values near 1.0 indicate parallel leg stance."
            ))
        }

        // 6. Body Centerline Deviation
        if let nose = pose[.nose], let lAnkle = pose[.leftAnkle], let rAnkle = pose[.rightAnkle] {
            let ankleCenter = (lAnkle.imageLocation.x + rAnkle.imageLocation.x) / 2.0
            let devPixel = nose.imageLocation.x - ankleCenter
            let devPercent = (devPixel / pose.imageWidth) * 100.0
            let dir = devPercent > 0 ? "right" : "left"
            let conf = min(nose.confidence, lAnkle.confidence, rAnkle.confidence)

            results.append(PostureMeasurement(
                id: .bodyCenterlineDeviation,
                name: "Body Centerline Deviation",
                value: roundToDecimal(abs(devPercent), 1),
                unit: "% frame width",
                landmarksUsed: [.nose, .leftAnkle, .rightAnkle],
                confidence: conf,
                explanation: "Head position deviates \(roundToDecimal(abs(devPercent), 1))% frame width to the \(dir) of ankle base midpoint."
            ))
        }

        return results
    }

    // MARK: - Side View Geometry

    private func analyzeSideView(pose: BodyPose, side: PostureView) -> [PostureMeasurement] {
        var results: [PostureMeasurement] = []

        let isLeft = (side == .leftSide)
        let ear = isLeft ? (pose[.leftEar] ?? pose[.rightEar]) : (pose[.rightEar] ?? pose[.leftEar])
        let shoulder = isLeft ? (pose[.leftShoulder] ?? pose[.rightShoulder]) : (pose[.rightShoulder] ?? pose[.leftShoulder])
        let hip = isLeft ? (pose[.leftHip] ?? pose[.rightHip]) : (pose[.rightHip] ?? pose[.leftHip])
        let knee = isLeft ? (pose[.leftKnee] ?? pose[.rightKnee]) : (pose[.rightKnee] ?? pose[.leftKnee])
        let ankle = isLeft ? (pose[.leftAnkle] ?? pose[.rightAnkle]) : (pose[.rightAnkle] ?? pose[.leftAnkle])

        // 1. Forward-Head Displacement & Ear-to-Shoulder Relationship
        if let ear = ear, let shoulder = shoulder {
            let angle = angleWithVerticalDegrees(p1: ear.imageLocation, p2: shoulder.imageLocation)
            let dxPixel = ear.imageLocation.x - shoulder.imageLocation.x
            let dxPercent = (dxPixel / pose.imageWidth) * 100.0
            let conf = min(ear.confidence, shoulder.confidence)

            results.append(PostureMeasurement(
                id: .forwardHeadAngle,
                name: "Forward Head Angle",
                value: roundToDecimal(abs(angle), 1),
                unit: "°",
                landmarksUsed: [ear.type, shoulder.type],
                confidence: conf,
                explanation: "Ear alignment relative to shoulder vertical axis is \(roundToDecimal(abs(angle), 1))°."
            ))

            results.append(PostureMeasurement(
                id: .earShoulderHorizontalOffset,
                name: "Ear-Shoulder Horizontal Offset",
                value: roundToDecimal(abs(dxPercent), 1),
                unit: "% frame width",
                landmarksUsed: [ear.type, shoulder.type],
                confidence: conf,
                explanation: "Ear is displaced \(roundToDecimal(abs(dxPercent), 1))% frame width from shoulder vertical."
            ))
        }

        // 2. Torso Inclination & Shoulder-to-Hip Alignment
        if let shoulder = shoulder, let hip = hip {
            let angle = angleWithVerticalDegrees(p1: shoulder.imageLocation, p2: hip.imageLocation)
            let conf = min(shoulder.confidence, hip.confidence)

            results.append(PostureMeasurement(
                id: .torsoInclinationAngle,
                name: "Torso Inclination Angle",
                value: roundToDecimal(abs(angle), 1),
                unit: "°",
                landmarksUsed: [shoulder.type, hip.type],
                confidence: conf,
                explanation: "Torso inclination from shoulder to hip relative to vertical line is \(roundToDecimal(abs(angle), 1))°."
            ))
        }

        // 3. Hip-to-Knee Alignment
        if let hip = hip, let knee = knee {
            let angle = angleWithVerticalDegrees(p1: hip.imageLocation, p2: knee.imageLocation)
            let conf = min(hip.confidence, knee.confidence)

            results.append(PostureMeasurement(
                id: .hipKneeAlignmentAngle,
                name: "Hip-Knee Alignment Angle",
                value: roundToDecimal(abs(angle), 1),
                unit: "°",
                landmarksUsed: [hip.type, knee.type],
                confidence: conf,
                explanation: "Hip-to-knee segment angle relative to vertical is \(roundToDecimal(abs(angle), 1))°."
            ))
        }

        // 4. Knee Angle / Extension
        if let hip = hip, let knee = knee, let ankle = ankle {
            let kAngle = vertexAngleDegrees(p1: hip.imageLocation, vertex: knee.imageLocation, p3: ankle.imageLocation)
            let conf = min(hip.confidence, knee.confidence, ankle.confidence)

            results.append(PostureMeasurement(
                id: .kneeJointAngle,
                name: "Knee Joint Angle",
                value: roundToDecimal(kAngle, 1),
                unit: "°",
                landmarksUsed: [hip.type, knee.type, ankle.type],
                confidence: conf,
                explanation: "Knee flexion/extension angle is \(roundToDecimal(kAngle, 1))° (180° corresponds to fully straight)."
            ))
        }

        // 5. Overall Sagittal-Body Lean (Ear/Shoulder to Ankle)
        if let topPoint = ear ?? shoulder, let ankle = ankle {
            let angle = angleWithVerticalDegrees(p1: topPoint.imageLocation, p2: ankle.imageLocation)
            let conf = min(topPoint.confidence, ankle.confidence)
            let leanDir = topPoint.imageLocation.x > ankle.imageLocation.x ? "forward" : "backward"

            results.append(PostureMeasurement(
                id: .overallSagittalBodyLean,
                name: "Overall Sagittal Body Lean",
                value: roundToDecimal(abs(angle), 1),
                unit: "°",
                landmarksUsed: [topPoint.type, ankle.type],
                confidence: conf,
                explanation: "Overall body centerline leans \(roundToDecimal(abs(angle), 1))° \(leanDir) relative to ankle base."
            ))
        }

        return results
    }

    // MARK: - Aspect-Correct Pixel Geometry Helpers

    /// Angle with horizontal axis in degrees (-90° to +90°) computed in top-left origin image pixel space.
    public func angleWithHorizontalDegrees(p1: CGPoint, p2: CGPoint) -> Double {
        let leftPt = p1.x <= p2.x ? p1 : p2
        let rightPt = p1.x <= p2.x ? p2 : p1
        let dx = rightPt.x - leftPt.x
        let dy = leftPt.y - rightPt.y // Invert dy so upward Y in image pixel space is positive dy
        guard dx != 0 || dy != 0 else { return 0 }
        guard dx != 0 else { return 90 }
        let radians = atan2(dy, dx)
        let degrees = radians * (180.0 / .pi)
        return degrees
    }

    /// Angle with vertical axis in degrees (-90° to +90°) computed in top-left origin image pixel space.
    public func angleWithVerticalDegrees(p1: CGPoint, p2: CGPoint) -> Double {
        // p1 is upper point, p2 is lower point
        let dx = p1.x - p2.x
        let dy = p2.y - p1.y // dy > 0 if p1 is physically above p2 (smaller pixel Y)
        let radians = atan2(dx, dy)
        let degrees = radians * (180.0 / .pi)
        return degrees
    }

    /// Angle formed at vertex by p1-vertex-p3 in degrees (0° to 180°).
    public func vertexAngleDegrees(p1: CGPoint, vertex: CGPoint, p3: CGPoint) -> Double {
        let v1 = CGPoint(x: p1.x - vertex.x, y: p1.y - vertex.y)
        let v2 = CGPoint(x: p3.x - vertex.x, y: p3.y - vertex.y)

        let dotProduct = v1.x * v2.x + v1.y * v2.y
        let mag1 = sqrt(v1.x * v1.x + v1.y * v1.y)
        let mag2 = sqrt(v2.x * v2.x + v2.y * v2.y)

        guard mag1 > 0 && mag2 > 0 else { return 0.0 }

        let cosTheta = max(-1.0, min(1.0, dotProduct / (mag1 * mag2)))
        let radians = acos(cosTheta)
        return radians * (180.0 / .pi)
    }

    private func roundToDecimal(_ value: Double, _ places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (value * divisor).rounded() / divisor
    }
}
