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

/// When a shoulder below the usual joint confidence still counts. With the face down at the bottom of a floor
/// push-up, Vision's shoulder confidence falls toward its floor while both arms stay clearly seen.
struct SupportedShoulderRule: Equatable {
    /// Lowest shoulder confidence accepted; a shoulder below it is dropped as usual.
    var minimumConfidence: Double
    /// Both elbows and both wrists must reach this confidence.
    var armConfidence: Double
    /// Farthest a supported shoulder may sit sideways from the last confident shoulder on its side, in that arm's
    /// length (upper arm + forearm).
    var maximumDrift: CGFloat
    /// A confident arm with at least this 2D elbow angle sets its side's ceiling (Up, for push-ups).
    var straightElbowAngle: Double
    /// The last confident shoulder is forgotten after this long without a usable shoulder on its side.
    var maximumGap: TimeInterval
}

/// Finds the shoulders a `SupportedShoulderRule` accepts below the usual confidence. Each must stay continuous with
/// the last confidently seen arm on its side: within the drift limit sideways, no higher than the shoulder in that
/// side's most recent confident straight-arm frame (the Up position for push-ups), and no lower than its own wrist.
/// Supported shoulders keep that reference alive but never move it, so a slow drift can't walk the reference away.
/// Only joints Vision saw count: an elbow or wrist estimated past the frame edge neither supports a shoulder nor
/// refreshes a reference.
struct SupportedShoulders {
    let rule: SupportedShoulderRule?
    /// The usual joint confidence; a whole arm at or above it refreshes that side's reference.
    let minimumConfidence: Double
    private var references: [BodySide: Reference] = [:]

    private struct Reference {
        var shoulder: CGPoint
        var armLength: CGFloat
        /// The shoulder height in the most recent confident straight-arm frame; nil until one is seen.
        var ceilingY: CGFloat?
        var lastUsable: TimeInterval
    }

    init(rule: SupportedShoulderRule?, minimumConfidence: Double) {
        self.rule = rule
        self.minimumConfidence = minimumConfidence
    }

    /// Updates the references from `frame` and returns the shoulders accepted below the usual confidence.
    mutating func update(_ frame: PoseFrame) -> Set<LandmarkType> {
        guard let rule else { return [] }
        let time = frame.timestamp
        func seen(_ joint: LandmarkType) -> CGPoint? {
            frame.estimatedJoints.contains(joint) ? nil : frame.point(joint, minimumConfidence: rule.armConfidence)
        }
        let armsSupport = BodySide.allCases.allSatisfy { seen($0.elbow) != nil && seen($0.wrist) != nil }
        var supported: Set<LandmarkType> = []
        for side in BodySide.allCases {
            if let arm = ArmGeometry.arm(side, in: frame, minimumConfidence: minimumConfidence),
               frame.estimatedJoints.isDisjoint(with: side.armJoints) {
                let ceiling = arm.elbowAngle >= rule.straightElbowAngle ? arm.shoulder.y : references[side]?.ceilingY
                references[side] = Reference(shoulder: arm.shoulder, armLength: arm.armLength,
                                             ceilingY: ceiling, lastUsable: time)
                continue
            }
            guard var reference = references[side] else { continue }
            guard time - reference.lastUsable <= rule.maximumGap + 0.000_001 else {
                references[side] = nil
                continue
            }
            guard armsSupport, let ceiling = reference.ceilingY,
                  let shoulder = frame.point(side.shoulder, minimumConfidence: rule.minimumConfidence),
                  let wrist = seen(side.wrist),
                  abs(shoulder.x - reference.shoulder.x) <= rule.maximumDrift * reference.armLength,
                  shoulder.y >= ceiling, shoulder.y <= wrist.y else { continue }
            reference.lastUsable = time
            references[side] = reference
            supported.insert(side.shoulder)
        }
        return supported
    }

    mutating func reset() {
        references.removeAll()
    }
}

/// Pixel-space arm and torso helpers. Pixel coordinates keep angles aspect-correct.
enum ArmGeometry {
    /// Joints in `supported` count at any confidence the frame kept, such as shoulders `SupportedShoulders` accepted.
    static func arm(_ side: BodySide, in frame: PoseFrame, minimumConfidence: Double,
                    supported: Set<LandmarkType> = []) -> ArmPoints? {
        func point(_ joint: LandmarkType) -> CGPoint? {
            supported.contains(joint) ? frame.pose[joint]?.imageLocation
                : frame.point(joint, minimumConfidence: minimumConfidence)
        }
        guard let shoulder = point(side.shoulder),
              let elbow = point(side.elbow),
              let wrist = point(side.wrist) else { return nil }
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

    /// Finds a knee on a two-segment chain. The bend direction chooses either side of the hip-to-ankle line;
    /// positive bends to the right in y-down image coordinates. Unreachable endpoints clamp to a straight leg.
    static func twoBoneKnee(hip: CGPoint, ankle: CGPoint, thighLength: CGFloat, shinLength: CGFloat,
                            bendDirection: CGFloat = 1) -> CGPoint {
        func finite(_ value: CGFloat) -> CGFloat { value.isFinite ? value : 0 }
        let upper = max(0, finite(thighLength))
        let lower = max(0, finite(shinLength))
        let start = CGPoint(x: finite(hip.x), y: finite(hip.y))
        let end = CGPoint(x: finite(ankle.x), y: finite(ankle.y))
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        guard upper > 0 else { return start }
        guard lower > 0 else { return end }
        guard distance > 0.000_001 else {
            return CGPoint(x: start.x + (bendDirection < 0 ? -upper : upper), y: start.y)
        }

        let minimumReach = abs(upper - lower)
        let maximumReach = upper + lower
        if distance >= maximumReach {
            let ratio = upper / distance
            return CGPoint(x: start.x + dx * ratio, y: start.y + dy * ratio)
        }

        let reach = max(minimumReach, distance)
        let along = (reach * reach + upper * upper - lower * lower) / (2 * reach)
        let across = sqrt(max(0, upper * upper - along * along))
        let unitX = dx / distance
        let unitY = dy / distance
        let side = bendDirection < 0 ? -1.0 : 1.0
        let alongX = unitX * along
        let bendX = unitY * across * side
        let alongY = unitY * along
        let bendY = -unitX * across * side
        return CGPoint(x: start.x + alongX + bendX,
                       y: start.y + alongY + bendY)
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
