import Foundation
@testable import PostureAnalysisApp

/// Push-Up motion sampled by the Movement Lab using the phone-on-the-floor guide geometry.
enum PushUpMovement {
    static let fullDepthElbowAngle = 80.0

    private static let guideMotion = PushUpExercise.definition().guide.motion

    /// Keeps the exercise guide's tempo and keyframe timing while giving the Lab an explicit counted depth.
    static let motion = makeMotion(bottomElbowAngle: fullDepthElbowAngle)

    /// Time from the start of the guide cycle until the descent begins.
    static var descentStartTime: TimeInterval {
        guard let index = downKeyframeIndex(in: guideMotion) else { return 0 }
        return guideMotion.keyframes[..<index].reduce(0) { $0 + $1.moveDuration + $1.holdDuration }
    }

    /// Time from the start of the guide cycle until the bottom hold begins.
    static var bottomTime: TimeInterval {
        guard let index = downKeyframeIndex(in: guideMotion) else { return descentStartTime }
        return descentStartTime + guideMotion.keyframes[index].moveDuration
    }

    /// Scales angular movement from the straight-arm start, matching the Lab's depthScale mutation.
    static func applyingDepthScale(to sample: ArmMotionSample, scale: Double) -> ArmMotionSample {
        var result = sample
        let start = guideMotion.startAngles
        result.angles = ArmAngles(
            upperArmElevation: start.upperArmElevation
                + (sample.angles.upperArmElevation - start.upperArmElevation) * scale,
            forearmElevation: start.forearmElevation
                + (sample.angles.forearmElevation - start.forearmElevation) * scale
        )
        return result
    }

    private static func makeMotion(bottomElbowAngle: Double) -> ArmMotion {
        guard let index = downKeyframeIndex(in: guideMotion) else { return guideMotion }
        var keyframes = guideMotion.keyframes
        guard keyframes.indices.contains(index) else { return guideMotion }
        keyframes[index].angles = ArmAngles(upperArmElevation: 0,
                                           forearmElevation: -(180 - bottomElbowAngle))
        return ArmMotion(keyframes: keyframes, forearmPlane: guideMotion.forearmPlane,
                         holdsDumbbells: guideMotion.holdsDumbbells, torsoPitch: guideMotion.torsoPitch,
                         wallPushUp: guideMotion.wallPushUp, inclinePushUp: guideMotion.inclinePushUp,
                         chair: guideMotion.chair)
    }

    private static func downKeyframeIndex(in motion: ArmMotion) -> Int? {
        guard let start = motion.keyframes.first?.angles else { return nil }
        return motion.keyframes.indices.dropFirst().max { left, right in
            angularDistance(motion.keyframes[left].angles, from: start)
                < angularDistance(motion.keyframes[right].angles, from: start)
        }
    }

    private static func angularDistance(_ angles: ArmAngles, from start: ArmAngles) -> Double {
        abs(angles.upperArmElevation - start.upperArmElevation)
            + abs(angles.forearmElevation - start.forearmElevation)
    }
}
