import CoreGraphics
import Foundation

/// The user's anatomical side, matching Vision's left/right joint labels.
/// In the unmirrored front-camera image the user's right side has the smaller x.
enum BodySide: String, CaseIterable, Hashable {
    case left
    case right

    var shoulder: LandmarkType { self == .left ? .leftShoulder : .rightShoulder }
    var elbow: LandmarkType { self == .left ? .leftElbow : .rightElbow }
    var wrist: LandmarkType { self == .left ? .leftWrist : .rightWrist }
    var hip: LandmarkType { self == .left ? .leftHip : .rightHip }
    var knee: LandmarkType { self == .left ? .leftKnee : .rightKnee }
    var ankle: LandmarkType { self == .left ? .leftAnkle : .rightAnkle }
    var armJoints: [LandmarkType] { [shoulder, elbow, wrist] }
    var legJoints: [LandmarkType] { [hip, knee, ankle] }
    var shortLabel: String { self == .left ? "L" : "R" }

    static func side(of joint: LandmarkType) -> BodySide? {
        allCases.first { $0.armJoints.contains(joint) || $0.legJoints.contains(joint) }
    }
}

/// Shoulder, elbow, and wrist in unmirrored image pixels.
struct ArmPoints {
    let shoulder: CGPoint
    let elbow: CGPoint
    let wrist: CGPoint

    var upperArmLength: CGFloat { ArmGeometry.distance(shoulder, elbow) }
    var forearmLength: CGFloat { ArmGeometry.distance(elbow, wrist) }
    var armLength: CGFloat { upperArmLength + forearmLength }
    /// Interior 2D elbow angle in degrees; 180 is a straight arm.
    var elbowAngle: Double { ArmGeometry.angle(at: elbow, shoulder, wrist) }
}

/// Both shoulders and hips in unmirrored image pixels.
struct TorsoPoints {
    let leftShoulder: CGPoint
    let rightShoulder: CGPoint
    let leftHip: CGPoint
    let rightHip: CGPoint

    var shoulderMidpoint: CGPoint { ArmGeometry.midpoint(leftShoulder, rightShoulder) }
    var hipMidpoint: CGPoint { ArmGeometry.midpoint(leftHip, rightHip) }
    /// Shoulder midpoint to hip midpoint; the scale for height ratios.
    var length: CGFloat { ArmGeometry.distance(shoulderMidpoint, hipMidpoint) }
    var shoulderWidth: CGFloat { ArmGeometry.distance(leftShoulder, rightShoulder) }
}

/// Pixel-space arm and torso helpers. Pixel coordinates keep angles aspect-correct.
enum ArmGeometry {
    static func arm(_ side: BodySide, in frame: PoseFrame, minimumConfidence: Double) -> ArmPoints? {
        guard let shoulder = frame.point(side.shoulder, minimumConfidence: minimumConfidence),
              let elbow = frame.point(side.elbow, minimumConfidence: minimumConfidence),
              let wrist = frame.point(side.wrist, minimumConfidence: minimumConfidence) else { return nil }
        return ArmPoints(shoulder: shoulder, elbow: elbow, wrist: wrist)
    }

    static func torso(in frame: PoseFrame, minimumConfidence: Double) -> TorsoPoints? {
        guard let leftShoulder = frame.point(.leftShoulder, minimumConfidence: minimumConfidence),
              let rightShoulder = frame.point(.rightShoulder, minimumConfidence: minimumConfidence),
              let leftHip = frame.point(.leftHip, minimumConfidence: minimumConfidence),
              let rightHip = frame.point(.rightHip, minimumConfidence: minimumConfidence) else { return nil }
        return TorsoPoints(leftShoulder: leftShoulder, rightShoulder: rightShoulder, leftHip: leftHip, rightHip: rightHip)
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }

    static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    /// Angle at `vertex` between rays to `a` and `b`, in degrees [0, 180].
    static func angle(at vertex: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        let v1 = CGVector(dx: a.x - vertex.x, dy: a.y - vertex.y)
        let v2 = CGVector(dx: b.x - vertex.x, dy: b.y - vertex.y)
        let lengths = hypot(v1.dx, v1.dy) * hypot(v2.dx, v2.dy)
        guard lengths > 0 else { return 0 }
        let cosine = max(-1, min(1, (v1.dx * v2.dx + v1.dy * v2.dy) / lengths))
        return Double(acos(cosine)) * 180 / .pi
    }
}
