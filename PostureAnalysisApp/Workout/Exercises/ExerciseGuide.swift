import CoreGraphics
import Foundation

/// Arm direction in degrees above horizontal, pointing away from the body:
/// 0 is straight out to the side, 90 straight up, -90 straight down.
struct ArmAngles: Equatable {
    var upperArmElevation: Double
    var forearmElevation: Double
}

/// How far a front-view figure has lowered into a squat.
struct LegPose: Equatable {
    /// Hip drop in standing thigh lengths: 0 standing, about 0.9 at thighs-parallel.
    var hipDrop: Double = 0
    /// Knees pushed outward, as a fraction of half the hip width.
    var kneeSpread: Double = 0

    static let standing = LegPose()
}

/// One pose in a looping demonstration.
struct ArmKeyframe {
    var angles: ArmAngles
    /// Time to move here from the previous keyframe; zero jumps.
    var moveDuration: TimeInterval
    var holdDuration: TimeInterval
    /// Guide step shown while moving to and holding this keyframe.
    var stepIndex: Int
    var legs: LegPose = .standing
}

struct ArmMotionSample: Equatable {
    var angles: ArmAngles
    var stepIndex: Int
    var legs: LegPose = .standing
}

/// The plane a forearm moves in, as seen by a front-facing camera.
enum MotionPlane: Equatable {
    /// Out to the side and up, as in a press: angles map straight onto the screen.
    case frontal
    /// Forward toward the camera, as in a curl: only the vertical part shows, so the forearm looks shorter.
    case sagittal
}

/// A looping two-arm demonstration. The guide figure and the live ghost both sample it, so they always agree.
struct ArmMotion {
    /// The first keyframe is the start position; the loop wraps from the last keyframe back to it.
    let keyframes: [ArmKeyframe]
    var forearmPlane: MotionPlane = .frontal
    /// False for band exercises, so the guide and ghost don't draw dumbbells.
    var holdsDumbbells = true
    /// Forward lean of the side-view figure's torso, in degrees from upright (for example, a bent-over row).
    var torsoPitch: Double = 0

    var duration: TimeInterval {
        keyframes.reduce(0) { $0 + $1.moveDuration + $1.holdDuration }
    }

    var startAngles: ArmAngles { keyframes.first?.angles ?? ArmAngles(upperArmElevation: 0, forearmElevation: 90) }

    var startLegs: LegPose { keyframes.first?.legs ?? .standing }

    /// The keyframe furthest from the start: the other end of the rep.
    private var topKeyframe: ArmKeyframe? {
        guard let first = keyframes.first else { return nil }
        func distance(_ keyframe: ArmKeyframe) -> Double {
            abs(keyframe.angles.upperArmElevation - first.angles.upperArmElevation)
                + abs(keyframe.angles.forearmElevation - first.angles.forearmElevation)
                + abs(keyframe.legs.hipDrop - first.legs.hipDrop) * 100
        }
        return keyframes.max { distance($0) < distance($1) }
    }

    var topAngles: ArmAngles { topKeyframe?.angles ?? startAngles }
    var topLegs: LegPose { topKeyframe?.legs ?? startLegs }

    /// The demonstration moves the legs, so the ghost shows legs rather than arms.
    var animatesLegs: Bool { keyframes.contains { $0.legs != .standing } }

    func sample(at time: TimeInterval) -> ArmMotionSample {
        guard let first = keyframes.first, duration > 0 else {
            return ArmMotionSample(angles: startAngles, stepIndex: keyframes.first?.stepIndex ?? 0, legs: startLegs)
        }
        let local = time.truncatingRemainder(dividingBy: duration)
        var elapsed = local < 0 ? local + duration : local
        var previous = keyframes.last ?? first
        for keyframe in keyframes {
            if elapsed < keyframe.moveDuration {
                let progress = Self.smoothstep(elapsed / keyframe.moveDuration)
                return ArmMotionSample(angles: Self.interpolate(previous.angles, keyframe.angles, progress),
                                       stepIndex: keyframe.stepIndex,
                                       legs: Self.interpolate(previous.legs, keyframe.legs, progress))
            }
            elapsed -= keyframe.moveDuration
            if elapsed < keyframe.holdDuration {
                return ArmMotionSample(angles: keyframe.angles, stepIndex: keyframe.stepIndex, legs: keyframe.legs)
            }
            elapsed -= keyframe.holdDuration
            previous = keyframe
        }
        return ArmMotionSample(angles: previous.angles, stepIndex: previous.stepIndex, legs: previous.legs)
    }

    /// Elbow and wrist for one arm in y-down coordinates. Outward is away from the other shoulder, so the
    /// same angles work in mirrored and unmirrored space.
    static func place(shoulder: CGPoint, otherShoulder: CGPoint, upperArm: CGFloat, forearm: CGFloat,
                      angles: ArmAngles, forearmPlane: MotionPlane = .frontal) -> (elbow: CGPoint, wrist: CGPoint) {
        place(shoulder: shoulder, outward: shoulder.x >= otherShoulder.x ? 1 : -1, upperArm: upperArm, forearm: forearm,
              angles: angles, forearmPlane: forearmPlane)
    }

    /// Elbow and wrist with an explicit outward direction: +1 toward larger x, -1 toward smaller x.
    static func place(shoulder: CGPoint, outward: CGFloat, upperArm: CGFloat, forearm: CGFloat,
                      angles: ArmAngles, forearmPlane: MotionPlane = .frontal) -> (elbow: CGPoint, wrist: CGPoint) {
        func step(from point: CGPoint, length: CGFloat, elevation: Double, plane: MotionPlane) -> CGPoint {
            let radians = elevation * .pi / 180
            let sideways = plane == .frontal ? outward * length * CGFloat(cos(radians)) : 0
            return CGPoint(x: point.x + sideways, y: point.y - length * CGFloat(sin(radians)))
        }
        let elbow = step(from: shoulder, length: upperArm, elevation: angles.upperArmElevation, plane: .frontal)
        return (elbow, step(from: elbow, length: forearm, elevation: angles.forearmElevation, plane: forearmPlane))
    }

    private static func smoothstep(_ value: Double) -> Double {
        let t = max(0, min(1, value))
        return t * t * (3 - 2 * t)
    }

    private static func interpolate(_ a: LegPose, _ b: LegPose, _ t: Double) -> LegPose {
        LegPose(hipDrop: a.hipDrop + (b.hipDrop - a.hipDrop) * t, kneeSpread: a.kneeSpread + (b.kneeSpread - a.kneeSpread) * t)
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
