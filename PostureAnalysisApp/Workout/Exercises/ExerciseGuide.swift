import CoreGraphics
import Foundation

/// Arm direction in degrees above horizontal, pointing away from the body:
/// 0 is straight out to the side, 90 straight up, -90 straight down.
struct ArmAngles: Equatable {
    var upperArmElevation: Double
    var forearmElevation: Double
}

/// One pose in a looping arm demonstration.
struct ArmKeyframe {
    var angles: ArmAngles
    /// Time to move here from the previous keyframe; zero jumps.
    var moveDuration: TimeInterval
    var holdDuration: TimeInterval
    /// Guide step shown while moving to and holding this keyframe.
    var stepIndex: Int
}

struct ArmMotionSample: Equatable {
    var angles: ArmAngles
    var stepIndex: Int
}

/// A looping two-arm demonstration. The guide figure and the live ghost both sample it, so they always agree.
struct ArmMotion {
    /// The first keyframe is the start position; the loop wraps from the last keyframe back to it.
    let keyframes: [ArmKeyframe]

    var duration: TimeInterval {
        keyframes.reduce(0) { $0 + $1.moveDuration + $1.holdDuration }
    }

    var startAngles: ArmAngles { keyframes.first?.angles ?? ArmAngles(upperArmElevation: 0, forearmElevation: 90) }

    /// The highest pose in the loop.
    var topAngles: ArmAngles {
        keyframes.max { $0.angles.upperArmElevation < $1.angles.upperArmElevation }?.angles ?? startAngles
    }

    func sample(at time: TimeInterval) -> ArmMotionSample {
        guard let first = keyframes.first, duration > 0 else {
            return ArmMotionSample(angles: startAngles, stepIndex: keyframes.first?.stepIndex ?? 0)
        }
        let local = time.truncatingRemainder(dividingBy: duration)
        var elapsed = local < 0 ? local + duration : local
        var previous = keyframes.last ?? first
        for keyframe in keyframes {
            if elapsed < keyframe.moveDuration {
                let progress = Self.smoothstep(elapsed / keyframe.moveDuration)
                return ArmMotionSample(angles: Self.interpolate(previous.angles, keyframe.angles, progress),
                                       stepIndex: keyframe.stepIndex)
            }
            elapsed -= keyframe.moveDuration
            if elapsed < keyframe.holdDuration {
                return ArmMotionSample(angles: keyframe.angles, stepIndex: keyframe.stepIndex)
            }
            elapsed -= keyframe.holdDuration
            previous = keyframe
        }
        return ArmMotionSample(angles: previous.angles, stepIndex: previous.stepIndex)
    }

    /// Elbow and wrist for one arm in y-down coordinates. Outward is away from the other shoulder, so the
    /// same angles work in mirrored and unmirrored space.
    static func place(shoulder: CGPoint, otherShoulder: CGPoint, upperArm: CGFloat, forearm: CGFloat,
                      angles: ArmAngles) -> (elbow: CGPoint, wrist: CGPoint) {
        let outward: CGFloat = shoulder.x >= otherShoulder.x ? 1 : -1
        func step(from point: CGPoint, length: CGFloat, elevation: Double) -> CGPoint {
            let radians = elevation * .pi / 180
            return CGPoint(x: point.x + outward * length * CGFloat(cos(radians)),
                           y: point.y - length * CGFloat(sin(radians)))
        }
        let elbow = step(from: shoulder, length: upperArm, elevation: angles.upperArmElevation)
        return (elbow, step(from: elbow, length: forearm, elevation: angles.forearmElevation))
    }

    private static func smoothstep(_ value: Double) -> Double {
        let t = max(0, min(1, value))
        return t * t * (3 - 2 * t)
    }

    private static func interpolate(_ a: ArmAngles, _ b: ArmAngles, _ t: Double) -> ArmAngles {
        ArmAngles(upperArmElevation: a.upperArmElevation + (b.upperArmElevation - a.upperArmElevation) * t,
                  forearmElevation: a.forearmElevation + (b.forearmElevation - a.forearmElevation) * t)
    }
}

struct GuideStep: Hashable {
    let title: String
    let detail: String
}

/// How an exercise is explained and demonstrated, in the guide and as the ghost over the user.
struct ExerciseGuide {
    let summary: String
    let steps: [GuideStep]
    let tip: String?
    /// Spoken by Read Aloud.
    let walkthrough: String
    /// Imperative start position, used in captions and prompts ("Hold the dumbbells just above your shoulders").
    let startPositionInstruction: String
    let motion: ArmMotion
}
