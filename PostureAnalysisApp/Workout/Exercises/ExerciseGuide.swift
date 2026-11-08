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

/// Body shape beyond the arms, specified independently for each motion keyframe. Torso pitch, hip shift,
/// hip drop, and stride shape standing side views; hip lift shapes the lying side view; shoulder lift shapes
/// the front view. Each view ignores the others' values, and the push-up floor view ignores them all.
struct FigureShape: Equatable {
    /// Torso lean in degrees from upright, toward the way the figure faces. `nil` uses `ArmMotion.torsoPitch`.
    var torsoPitch: Double? = nil
    /// Hips pushed back behind the planted ankle, in standing thigh lengths.
    var hipShift: Double = 0
    /// Hips lowered, in standing leg lengths (standing hip-to-ankle).
    var hipDrop: Double = 0
    /// Rear foot stepped back behind the front foot, in standing leg lengths.
    var stride: Double = 0
    /// Front view: both shoulders raised toward the ears, in figure upper-arm lengths (0 is relaxed).
    var shoulderLift: Double = 0
    /// Lying side view: 0 is hips resting on the floor, 1 aligns shoulder, hip, and knee.
    var hipLift: Double = 0

    static let neutral = FigureShape()

    /// The side-view fields only, so a front-view shoulder lift never reads as side-body motion.
    fileprivate var sideBody: FigureShape {
        FigureShape(torsoPitch: torsoPitch, hipShift: hipShift, hipDrop: hipDrop, stride: stride,
                    hipLift: hipLift)
    }
}

/// A chair's seat as a horizontal segment in guide-canvas points.
struct ChairSeat: Equatable {
    var from: CGPoint
    var to: CGPoint
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
    var shape: FigureShape = .neutral
}

struct ArmMotionSample: Equatable {
    var angles: ArmAngles
    var stepIndex: Int
    var legs: LegPose = .standing
    /// Resolved samples always have a non-nil torso pitch.
    var shape: FigureShape = FigureShape(torsoPitch: 0)
    /// Uses the planted-hand wall layout instead of the generic standing side figure.
    var wallPushUp = false
    /// Uses the planted-hand bench layout instead of the generic standing side figure.
    var inclinePushUp = false

    /// The planted-hand layout this sample draws, if it is a push-up against a fixed surface.
    var plantedLayout: PlantedBodyLayout? {
        PlantedBodyLayout.layout(wallPushUp: wallPushUp, inclinePushUp: inclinePushUp)
    }
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
    /// Draw a side-view wall push-up with fixed wrists and a straight body line.
    var wallPushUp = false
    /// Draw a side-view incline push-up with fixed wrists on a bench and a straight body line.
    var inclinePushUp = false
    /// Draw a seat line behind a front-view figure that starts seated. The ghost then sizes itself from the
    /// shins, which stay upright when seated, because a seated thigh points at the camera and looks short.
    var chair = false

    /// The planted-hand layout this motion draws, if it is a push-up against a fixed surface.
    var plantedLayout: PlantedBodyLayout? {
        PlantedBodyLayout.layout(wallPushUp: wallPushUp, inclinePushUp: inclinePushUp)
    }

    /// The chair's seat in guide-canvas points, just under the hips of the start pose; nil without a chair.
    var chairSeat: ChairSeat? {
        chair ? ExerciseDemoFigureView.chairSeat(for: startLegs) : nil
    }

    var duration: TimeInterval {
        keyframes.reduce(0) { $0 + $1.moveDuration + $1.holdDuration }
    }

    var startAngles: ArmAngles { keyframes.first?.angles ?? ArmAngles(upperArmElevation: 0, forearmElevation: 90) }

    var startLegs: LegPose { keyframes.first?.legs ?? .standing }

    var startSample: ArmMotionSample {
        guard let first = keyframes.first else {
            return ArmMotionSample(angles: startAngles, stepIndex: 0, legs: startLegs,
                                   shape: FigureShape(torsoPitch: torsoPitch), wallPushUp: wallPushUp,
                                   inclinePushUp: inclinePushUp)
        }
        return sample(of: first)
    }

    /// The keyframe furthest from the start: the other end of the rep.
    private var topKeyframe: ArmKeyframe? {
        guard let first = keyframes.first else { return nil }
        func distance(_ keyframe: ArmKeyframe) -> Double {
            let firstShape = Self.resolvedShape(first.shape, torsoPitch: torsoPitch)
            let shape = Self.resolvedShape(keyframe.shape, torsoPitch: torsoPitch)
            let upperArmDistance = abs(keyframe.angles.upperArmElevation - first.angles.upperArmElevation)
            let forearmDistance = abs(keyframe.angles.forearmElevation - first.angles.forearmElevation)
            let legDistance = abs(keyframe.legs.hipDrop - first.legs.hipDrop) * 100
            let torsoDistance = abs((shape.torsoPitch ?? 0) - (firstShape.torsoPitch ?? 0))
            let hipShiftDistance = abs(shape.hipShift - firstShape.hipShift)
            let hipDropDistance = abs(shape.hipDrop - firstShape.hipDrop)
            let strideDistance = abs(shape.stride - firstShape.stride)
            let shoulderLiftDistance = abs(shape.shoulderLift - firstShape.shoulderLift)
            let hipLiftDistance = abs(shape.hipLift - firstShape.hipLift)
            let shapeDistance = hipShiftDistance + hipDropDistance + strideDistance
                + shoulderLiftDistance + hipLiftDistance
            return upperArmDistance + forearmDistance + legDistance + torsoDistance + shapeDistance * 100
        }
        return keyframes.max { distance($0) < distance($1) }
    }

    var topAngles: ArmAngles { topKeyframe?.angles ?? startAngles }
    var topLegs: LegPose { topKeyframe?.legs ?? startLegs }
    var topSample: ArmMotionSample {
        guard let topKeyframe else { return startSample }
        return sample(of: topKeyframe)
    }

    /// The demonstration moves the legs, so the ghost shows legs rather than arms.
    var animatesLegs: Bool { keyframes.contains { $0.legs != .standing } }

    /// Side-view body geometry changes over the motion. A constant motion-level pitch, as on the row, is a pose
    /// default rather than side-body motion.
    var movesSideBody: Bool {
        guard let first = keyframes.first else { return false }
        let start = Self.resolvedShape(first.shape, torsoPitch: torsoPitch).sideBody
        return keyframes.contains { keyframe in
            let shape = Self.resolvedShape(keyframe.shape, torsoPitch: torsoPitch).sideBody
            return shape != start || shape.hipShift != 0 || shape.hipDrop != 0
                || shape.stride != 0 || shape.hipLift != 0
        }
    }

    /// Returns a keyframe with the motion-level pitch filled in when the frame does not override it.
    func sample(of keyframe: ArmKeyframe) -> ArmMotionSample {
        ArmMotionSample(angles: keyframe.angles, stepIndex: keyframe.stepIndex, legs: keyframe.legs,
                       shape: Self.resolvedShape(keyframe.shape, torsoPitch: torsoPitch),
                       wallPushUp: wallPushUp, inclinePushUp: inclinePushUp)
    }

    func sample(at time: TimeInterval) -> ArmMotionSample {
        guard let first = keyframes.first, duration > 0 else {
            return startSample
        }
        let local = time.truncatingRemainder(dividingBy: duration)
        var elapsed = local < 0 ? local + duration : local
        var previous = keyframes.last ?? first
        for keyframe in keyframes {
            if elapsed < keyframe.moveDuration {
                let progress = Self.smoothstep(elapsed / keyframe.moveDuration)
                let previousSample = sample(of: previous)
                let targetSample = sample(of: keyframe)
                return ArmMotionSample(angles: Self.interpolate(previous.angles, keyframe.angles, progress),
                                       stepIndex: keyframe.stepIndex,
                                       legs: Self.interpolate(previous.legs, keyframe.legs, progress),
                                       shape: Self.interpolate(previousSample.shape, targetSample.shape, progress),
                                       wallPushUp: wallPushUp, inclinePushUp: inclinePushUp)
            }
            elapsed -= keyframe.moveDuration
            if elapsed < keyframe.holdDuration {
                return sample(of: keyframe)
            }
            elapsed -= keyframe.holdDuration
            previous = keyframe
        }
        return sample(of: previous)
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

    private static func resolvedShape(_ shape: FigureShape, torsoPitch: Double) -> FigureShape {
        FigureShape(torsoPitch: shape.torsoPitch ?? torsoPitch,
                    hipShift: shape.hipShift, hipDrop: shape.hipDrop, stride: shape.stride,
                    shoulderLift: shape.shoulderLift, hipLift: shape.hipLift)
    }

    private static func interpolate(_ a: FigureShape, _ b: FigureShape, _ t: Double) -> FigureShape {
        FigureShape(torsoPitch: (a.torsoPitch ?? 0) + ((b.torsoPitch ?? 0) - (a.torsoPitch ?? 0)) * t,
                    hipShift: a.hipShift + (b.hipShift - a.hipShift) * t,
                    hipDrop: a.hipDrop + (b.hipDrop - a.hipDrop) * t,
                    stride: a.stride + (b.stride - a.stride) * t,
                    shoulderLift: a.shoulderLift + (b.shoulderLift - a.shoulderLift) * t,
                    hipLift: a.hipLift + (b.hipLift - a.hipLift) * t)
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
