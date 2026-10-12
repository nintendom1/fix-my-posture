import CoreGraphics
import Foundation

/// From the side, picks the arm nearer the phone: the most confident complete arm, staying with the current
/// one unless the other is clearly more confident, so tracking doesn't flip between overlapping arms.
struct NearArmSelector {
    /// The other arm must be this much more confident before tracking switches to it.
    static let switchMargin = 0.2
    private(set) var side: BodySide?

    /// The arm to track, and whether tracking just switched to it.
    mutating func select(in frame: PoseFrame, minimumConfidence: Double) -> (side: BodySide, arm: ArmPoints, switched: Bool)? {
        let candidates = BodySide.allCases.compactMap { side -> (BodySide, ArmPoints, Double)? in
            guard let arm = ArmGeometry.arm(side, in: frame, minimumConfidence: minimumConfidence) else { return nil }
            let confidence = side.armJoints.compactMap { frame.pose[$0]?.confidence }.min() ?? 0
            return (side, arm, confidence)
        }
        guard let best = candidates.max(by: { $0.2 < $1.2 }) else { return nil }
        var choice = best
        if let current = candidates.first(where: { $0.0 == side }), best.2 - current.2 < Self.switchMargin {
            choice = current
        }
        let switched = choice.0 != side
        side = choice.0
        return (choice.0, choice.1, switched)
    }
}
