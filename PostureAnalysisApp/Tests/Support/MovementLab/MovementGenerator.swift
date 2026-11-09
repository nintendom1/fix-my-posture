import CoreGraphics
import Foundation
@testable import PostureAnalysisApp

/// One synchronized canonical and modified sample on the scenario timeline.
struct MovementMaterializedFrame {
    let frame: PoseFrame
    let referenceFrame: PoseFrame
    let elapsed: TimeInterval
}

/// The deterministic frame sequence and replayable recording lines for one scenario.
struct MovementMaterialization {
    let frames: [MovementMaterializedFrame]
    let recordingLines: [String]
    let invalidReasons: [String]

    var isValid: Bool { invalidReasons.isEmpty }
}

/// Samples an exercise guide and applies scenario mutations in a fixed, reproducible order.
enum MovementGenerator {
    static let framesPerSecond = 30.0
    static let imageSize = CGSize(width: 1080, height: 1920)
    static let readyHold = MovementSequenceDurations.readyHold

    private struct RepSegment {
        var rep: Int
        var start: TimeInterval
        var duration: TimeInterval
        var tempoScale: Double
    }

    static func materialize(plan: MovementPlan, scenario: MovementScenario,
                            startingTimestamp: TimeInterval = 0) -> MovementMaterialization {
        var invalidReasons = scenario.validate().map(\.message)
        guard let exercise = ExerciseCatalog.all.first(where: { $0.id == scenario.exercise }) else {
            return invalid(["Unknown exercise \(scenario.exercise.rawValue)."])
        }
        guard scenario.canonicalRevision == MovementCanonicalRevision.value(for: exercise) else {
            invalidReasons.append("The canonical exercise guide changed; refresh canonicalRevision before materializing.")
            return invalid(invalidReasons)
        }
        guard startingTimestamp.isFinite else {
            return invalid(["startingTimestamp must be finite."])
        }
        guard MovementISO8601.date(from: plan.createdAt) != nil else {
            return invalid(["createdAt must be a valid ISO 8601 date-time."])
        }
        guard invalidReasons.isEmpty else { return invalid(invalidReasons) }

        if scenario.mode == .constrained {
            for mutation in scenario.mutations {
                guard case .jointOffset(_, let dx, let dy, _, _, _, let strength) = mutation else { continue }
                if hypot(dx, dy) * strength > 0.3 {
                    return invalid(["Constrained projection cannot satisfy a joint offset larger than 0.3 body-heights."])
                }
            }
        }

        let motion = exercise.guide.motion
        guard let pauses = MovementSequenceDurations.pauseSegments(in: scenario.mutations) else {
            return invalid(["Pause timeline values must be finite and nonnegative."])
        }
        var segments: [RepSegment] = []
        var cursor = readyHold
        for rep in 1...scenario.reps {
            guard let scale = MovementSequenceDurations.tempoScale(for: rep, mutations: scenario.mutations) else {
                return invalid(["Composite tempo must remain finite and positive."])
            }
            guard let duration = MovementSequenceDurations.repetitionDuration(
                for: rep, motionDuration: motion.duration, mutations: scenario.mutations
            ) else {
                return invalid(["Tempo-scaled repetition duration must remain finite and positive."])
            }
            segments.append(RepSegment(rep: rep, start: cursor, duration: duration, tempoScale: scale))
            guard let next = MovementSequenceDurations.adding(duration, to: cursor) else {
                return invalid(["Scenario duration exceeds the finite timeline range."])
            }
            cursor = next
        }
        var totalDuration = cursor
        for pause in pauses {
            guard let next = MovementSequenceDurations.adding(pause.duration, to: totalDuration) else {
                return invalid(["Scenario duration exceeds the finite timeline range."])
            }
            totalDuration = next
        }
        guard totalDuration >= 0, totalDuration <= 120 else {
            return invalid(["Scenario duration exceeds the 120-second materialization limit."])
        }
        let frameCount = Int(ceil(totalDuration * framesPerSecond)) + 1
        guard frameCount > 0 else { return invalid(["Scenario frame count must be positive."]) }

        let startTime = readyHold
        let startFrame = ReadyPoseFixtures.demoFrame(exercise, motionTime: 0, at: 0)
        var random = SplitMix64(seed: scenario.seed)
        var outputFrames: [MovementMaterializedFrame] = []

        for index in 0..<frameCount {
            let elapsed = Double(index) / framesPerSecond
            let guideTime = Self.guideTime(at: elapsed, pauses: pauses)
            let segment = segments.first { guideTime >= $0.start && guideTime < $0.start + $0.duration }
            let repIndex = segment?.rep
            let motionTime: TimeInterval
            if let segment {
                motionTime = min(motion.duration, max(0, (guideTime - segment.start) / segment.tempoScale))
            } else if guideTime < readyHold || guideTime >= cursor {
                motionTime = 0
            } else {
                motionTime = max(0, guideTime - startTime)
            }

            let referenceFrame = ReadyPoseFixtures.demoFrame(exercise, motionTime: motionTime,
                                                              at: startingTimestamp + elapsed)
            let guidePoints = coordinates(in: referenceFrame.pose)
            var points = guidePoints
            let bodyHeight = max(1, bodyHeight(of: points))
            var targetJoints = Set<LandmarkType>()
            var depthTargetJoints = Set<LandmarkType>()
            var exactTargetJoints = Set<LandmarkType>()

            // 1. Seeded pixel jitter is bounded to 0.002 body-heights per axis.
            for joint in LandmarkType.allCases where points[joint] != nil {
                guard let point = points[joint] else { continue }
                let jitterX = CGFloat(random.signedUnit() * 0.002 * bodyHeight)
                let jitterY = CGFloat(random.signedUnit() * 0.002 * bodyHeight)
                points[joint] = CGPoint(x: point.x + jitterX, y: point.y + jitterY)
            }

            // 2. Range mutations move the hips and knees relative to the guide's standing pose.
            for mutation in scenario.mutations {
                guard case .depthScale(let scale, let selectedReps) = mutation,
                      let repIndex, selectedReps == nil || selectedReps?.contains(repIndex) == true else { continue }
                let depthJoints: [LandmarkType] = [.leftHip, .rightHip, .leftKnee, .rightKnee]
                for joint in depthJoints {
                    guard let current = points[joint], let standing = startFrame.pose[joint]?.imageLocation else { continue }
                    points[joint] = CGPoint(x: standing.x + (current.x - standing.x) * scale,
                                            y: standing.y + (current.y - standing.y) * scale)
                    if scale != 1, joint == .leftHip || joint == .rightHip { depthTargetJoints.insert(joint) }
                }
            }

            // 3. Asymmetry follows squat depth so standing stays level.
            let sample = motion.sample(at: motionTime)
            let depthRatio = min(1, max(0, sample.legs.hipDrop / max(0.001, motion.topLegs.hipDrop)))
            for mutation in scenario.mutations {
                guard case .asymmetry(let side, let amount) = mutation else { continue }
                for (joint, factor) in [(side.hip, 1.0), (side.knee, 0.5)] {
                    guard let point = points[joint] else { continue }
                    let shifted = CGPoint(x: point.x,
                                          y: point.y + CGFloat(amount * depthRatio * bodyHeight * factor))
                    points[joint] = shifted
                    if joint == side.hip, ArmGeometry.distance(point, shifted) > 0.01 { targetJoints.insert(joint) }
                }
            }

            // 4. Local landmark edits use the raised-cosine influence curve.
            for mutation in scenario.mutations {
                guard case .jointOffset(let jointNames, let dx, let dy, let peak, let rise, let fall, let strength) = mutation else { continue }
                let influence = MovementInfluence.weight(at: elapsed, peak: peak, rise: rise, fall: fall) * strength
                guard influence > 0 else { continue }
                for name in jointNames {
                    guard let joint = LandmarkType(rawValue: name), let point = points[joint] else { continue }
                    guard dx != 0 || dy != 0 else { continue }
                    points[joint] = CGPoint(x: point.x + CGFloat(dx * bodyHeight * influence),
                                            y: point.y + CGFloat(dy * bodyHeight * influence))
                    targetJoints.insert(joint)
                    exactTargetJoints.insert(joint)
                }
            }

            // 5. Constrained edits project onto canonical bone lengths and keep both ankles planted.
            if scenario.mode == .constrained {
                let requestedPoints = points
                for ankle in [LandmarkType.leftAnkle, .rightAnkle] {
                    if targetJoints.contains(ankle), let requested = requestedPoints[ankle],
                       let planted = guidePoints[ankle], ArmGeometry.distance(requested, planted) > 0.01 {
                        return invalid(["Constrained projection cannot move planted landmark \(ankle.rawValue)."])
                    }
                    if let planted = guidePoints[ankle] { points[ankle] = planted }
                }
                if let reason = constrain(&points, reference: guidePoints, requested: requestedPoints,
                                          planted: [.leftAnkle, .rightAnkle], targetJoints: targetJoints,
                                          depthTargetJoints: depthTargetJoints,
                                          exactTargetJoints: exactTargetJoints) {
                    invalidReasons.append(reason)
                    return invalid(invalidReasons)
                }
            }

            // 6. Framing is a camera transform, followed by confidence and visibility changes.
            for mutation in scenario.mutations {
                guard case .framing(let scale, let offsetX, let offsetY) = mutation else { continue }
                let center = CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
                for (joint, point) in Array(points) {
                    points[joint] = CGPoint(x: center.x + (point.x - center.x) * scale
                                                + CGFloat(offsetX * bodyHeight),
                                            y: center.y + (point.y - center.y) * scale
                                                + CGFloat(offsetY * bodyHeight))
                }
            }

            var confidenceOverrides: [LandmarkType: Double] = [:]
            var dropped = Set<LandmarkType>()
            for mutation in scenario.mutations {
                switch mutation {
                case .dropout(let jointNames, let from, let to) where elapsed >= from && elapsed < to:
                    dropped.formUnion(jointNames.compactMap(LandmarkType.init(rawValue:)))
                case .confidence(let jointNames, let from, let to, let confidence)
                    where elapsed >= from && elapsed < to:
                    for joint in jointNames.compactMap(LandmarkType.init(rawValue:)) {
                        confidenceOverrides[joint] = confidence
                    }
                default:
                    continue
                }
            }

            let inGap = scenario.mutations.contains { mutation in
                guard case .frameGap(let at, let duration) = mutation else { return false }
                return elapsed >= at && elapsed < at + duration
            }
            if inGap { continue }

            var pose = referenceFrame.pose
            for joint in LandmarkType.allCases {
                guard var landmark = pose[joint], let point = points[joint] else { continue }
                landmark.imageLocation = point
                landmark.normalizedLocation = CoordinateConverter.imagePixelToNormalized(
                    pixel: point, imageWidth: imageSize.width, imageHeight: imageSize.height)
                if let confidence = confidenceOverrides[joint] { landmark.confidence = confidence }
                pose[joint] = landmark
            }
            for joint in dropped { pose[joint] = nil }

            let timestamp = startingTimestamp + elapsed
            let frame = PoseFrame(pose: pose, timestamp: timestamp)
            outputFrames.append(MovementMaterializedFrame(frame: frame, referenceFrame: referenceFrame,
                                                          elapsed: elapsed))
        }

        let lines = MovementMaterializer.recordingLines(plan: plan, scenario: scenario, exercise: exercise,
                                                        frames: outputFrames)
        return MovementMaterialization(frames: outputFrames, recordingLines: lines, invalidReasons: [])
    }

    private static func invalid(_ reasons: [String]) -> MovementMaterialization {
        MovementMaterialization(frames: [], recordingLines: [], invalidReasons: reasons)
    }

    /// Removes inserted pause time to recover the guide-clock position.
    private static func guideTime(at outputTime: TimeInterval,
                                  pauses: [(at: TimeInterval, duration: TimeInterval)]) -> TimeInterval {
        var inserted: TimeInterval = 0
        for pause in pauses {
            let outputStart = pause.at + inserted
            if outputTime < outputStart { return outputTime - inserted }
            if outputTime < outputStart + pause.duration { return pause.at }
            inserted += pause.duration
        }
        return outputTime - inserted
    }

    private static func coordinates(in pose: BodyPose) -> [LandmarkType: CGPoint] {
        Dictionary(uniqueKeysWithValues: pose.landmarks.map { ($0.key, $0.value.imageLocation) })
    }

    private static func bodyHeight(of points: [LandmarkType: CGPoint]) -> Double {
        guard let minimum = points.values.map(\.y).min(), let maximum = points.values.map(\.y).max() else { return 1 }
        return Double(maximum - minimum)
    }

    /// Position-based distance projection. Feet and explicit local-offset targets are fixed; higher-level edited
    /// joints resist movement, and all connected bones target the guide lengths for this sample. Failure is explicit.
    private static func constrain(_ points: inout [LandmarkType: CGPoint], reference: [LandmarkType: CGPoint],
                                  requested: [LandmarkType: CGPoint],
                                  planted: Set<LandmarkType>, targetJoints: Set<LandmarkType>,
                                  depthTargetJoints: Set<LandmarkType>,
                                  exactTargetJoints: Set<LandmarkType>) -> String? {
        for _ in 0..<80 {
            for (first, second) in BodyPose.connections {
                guard let referenceFirst = reference[first], let referenceSecond = reference[second],
                      let firstPoint = points[first], let secondPoint = points[second] else { continue }
                let targetLength = ArmGeometry.distance(referenceFirst, referenceSecond)
                guard targetLength > 0.000_1 else { continue }
                let dx = secondPoint.x - firstPoint.x
                let dy = secondPoint.y - firstPoint.y
                let length = hypot(dx, dy)
                guard length > 0.000_1 else { continue }
                let error = length - targetLength
                let firstWeight: CGFloat = planted.contains(first) || exactTargetJoints.contains(first) ? 0
                    : (depthTargetJoints.contains(first) ? 0.5 : (targetJoints.contains(first) ? 0.05 : 1))
                let secondWeight: CGFloat = planted.contains(second) || exactTargetJoints.contains(second) ? 0
                    : (depthTargetJoints.contains(second) ? 0.5 : (targetJoints.contains(second) ? 0.05 : 1))
                let weight = firstWeight + secondWeight
                guard weight > 0 else { continue }
                let correctionX = dx / length * error
                let correctionY = dy / length * error
                if firstWeight > 0, let point = points[first] {
                    points[first] = CGPoint(x: point.x + correctionX * firstWeight / weight,
                                            y: point.y + correctionY * firstWeight / weight)
                }
                if secondWeight > 0, let point = points[second] {
                    points[second] = CGPoint(x: point.x - correctionX * secondWeight / weight,
                                             y: point.y - correctionY * secondWeight / weight)
                }
            }
        }

        for (first, second) in BodyPose.connections {
            guard let referenceFirst = reference[first], let referenceSecond = reference[second],
                  let firstPoint = points[first], let secondPoint = points[second] else { continue }
            let targetLength = ArmGeometry.distance(referenceFirst, referenceSecond)
            guard targetLength > 0.000_1 else { continue }
            let difference = abs(ArmGeometry.distance(firstPoint, secondPoint) - targetLength) / targetLength
            if difference > 0.03 {
                return "Constrained projection could not keep \(first.rawValue)–\(second.rawValue) within 3% of its guide length."
            }
        }
        for joint in orderedLandmarks(in: planted) {
            guard let expected = reference[joint], let actual = points[joint],
                  ArmGeometry.distance(expected, actual) <= 0.01 else {
                return "Constrained projection moved planted landmark \(joint.rawValue)."
            }
        }
        for joint in orderedLandmarks(in: exactTargetJoints) {
            guard let requested = requested[joint], let reference = reference[joint], let actual = points[joint] else { continue }
            let requestedDistance = ArmGeometry.distance(requested, reference)
            guard requestedDistance > 1 else { continue }
            if ArmGeometry.distance(actual, requested) > requestedDistance * 0.5 {
                return "Constrained projection could not retain half of the requested \(joint.rawValue) displacement."
            }
        }
        return nil
    }

    static func orderedLandmarks(in joints: Set<LandmarkType>) -> [LandmarkType] {
        LandmarkType.allCases.filter(joints.contains)
    }
}

/// Writes synthetic frames with the application's existing session-recording line builders.
enum MovementMaterializer {
    static func recordingLines(plan: MovementPlan, scenario: MovementScenario, exercise: ExerciseDefinition,
                               frames: [MovementMaterializedFrame]) -> [String] {
        guard let startedAt = MovementISO8601.date(from: plan.createdAt) else { return [] }
        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        let context = WorkoutRecordingContext(startedAt: startedAt, timeZone: utc, exercises: [exercise], plan: nil,
                                              settings: WorkoutSettings(startByHolding: false),
                                              tiltWarningsEnabled: false, isCoachMuted: true, isMicMuted: true)
        let app = WorkoutSessionLines.AppInfo(version: "1", build: "1", configuration: "MovementLab",
                                              deviceModel: "synthetic", systemVersion: "1")
        var lines = [WorkoutSessionLines.header(id: recordingID(plan: plan, scenario: scenario),
                                                context: context, app: app).serialized]
        lines.append(WorkoutSessionLines.control(.sessionPhase(.ready), t: 0).serialized)
        lines.append(WorkoutSessionLines.control(.exercise(exercise, analyzerEpoch: 1), t: 0).serialized)
        lines.append(WorkoutSessionLines.control(.sessionPhase(.exercising), t: 0).serialized)
        lines.append(WorkoutSessionLines.control(.counting(true), t: 0).serialized)
        for (index, sample) in frames.enumerated() {
            let serialized = WorkoutSessionLines.frame(sample.frame, output: nil, pitchDegrees: nil,
                                                       imageSizeChanged: index == 0, t: sample.elapsed).serialized
            // The frame builder owns ordering and exact joint encoding. Mark it analyzed for replay's input format;
            // the next milestone will record actual analyzer output in these same lines.
            lines.append(serialized.replacingOccurrences(of: "\"p\":false", with: "\"p\":true"))
        }
        if let finalTime = frames.last?.elapsed {
            lines.append(WorkoutSessionLines.control(.counting(false), t: finalTime).serialized)
            lines.append(WorkoutSessionLines.end(.workoutEnded, endedAt: startedAt.addingTimeInterval(finalTime),
                                                  timeZone: utc, frames: frames.count, sequenceGaps: 0,
                                                  workoutRecordID: nil, t: finalTime).serialized)
        }
        return lines
    }

    private static func recordingID(plan: MovementPlan, scenario: MovementScenario) -> UUID {
        let input = "\(plan.id)|\(scenario.id)|\(scenario.revision)"
        var first: UInt64 = 1_469_598_103_934_665_603
        var second: UInt64 = 1_099_511_628_211
        for byte in input.utf8 {
            first = (first ^ UInt64(byte)) &* 1_099_511_628_211
            second = (second ^ UInt64(byte &+ 31)) &* 1_099_511_628_211
        }
        return UUID(uuid: (UInt8(truncatingIfNeeded: first >> 56), UInt8(truncatingIfNeeded: first >> 48),
                            UInt8(truncatingIfNeeded: first >> 40), UInt8(truncatingIfNeeded: first >> 32),
                            UInt8(truncatingIfNeeded: first >> 24), UInt8(truncatingIfNeeded: first >> 16),
                            UInt8(truncatingIfNeeded: first >> 8), UInt8(truncatingIfNeeded: first),
                            UInt8(truncatingIfNeeded: second >> 56), UInt8(truncatingIfNeeded: second >> 48),
                            UInt8(truncatingIfNeeded: second >> 40), UInt8(truncatingIfNeeded: second >> 32),
                            UInt8(truncatingIfNeeded: second >> 24), UInt8(truncatingIfNeeded: second >> 16),
                            UInt8(truncatingIfNeeded: second >> 8), UInt8(truncatingIfNeeded: second)))
    }
}

/// Revision hash over the guide motion's keyframe values and drawing settings.
enum MovementCanonicalRevision {
    static func value(for exercise: ExerciseDefinition) -> String {
        value(for: exercise.id, motion: exercise.guide.motion)
    }

    static func value(for exercise: ExerciseID, motion: ArmMotion) -> String {
        var fields = [exercise.rawValue, String(motion.duration), String(motion.holdsDumbbells),
                      String(motion.torsoPitch), String(motion.wallPushUp), String(motion.inclinePushUp),
                      String(motion.chair)]
        switch motion.forearmPlane {
        case .frontal: fields.append("frontal")
        case .sagittal: fields.append("sagittal")
        }
        for frame in motion.keyframes {
            fields.append(contentsOf: [String(frame.angles.upperArmElevation), String(frame.angles.forearmElevation),
                                       String(frame.moveDuration), String(frame.holdDuration), String(frame.stepIndex),
                                       String(frame.legs.hipDrop), String(frame.legs.kneeSpread),
                                       frame.shape.torsoPitch.map { "explicit:\($0)" } ?? "inherited-torso-pitch",
                                       String(frame.shape.hipShift),
                                       String(frame.shape.hipDrop), String(frame.shape.stride),
                                       String(frame.shape.shoulderLift), String(frame.shape.hipLift)])
        }
        let bytes = fields.joined(separator: "|").utf8
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in bytes { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return "guide-fnv1a-\(String(hash, radix: 16))"
    }
}

/// Guide timing helpers account for each keyframe's movement and hold duration.
enum MovementGuideTimeline {
    static func maximumHipDropTime(in motion: ArmMotion) -> TimeInterval {
        let maximum = motion.keyframes.map(\.legs.hipDrop).max() ?? motion.startLegs.hipDrop
        var elapsed = 0.0
        for keyframe in motion.keyframes {
            elapsed += keyframe.moveDuration
            if keyframe.legs.hipDrop == maximum { return elapsed }
            elapsed += keyframe.holdDuration
        }
        return 0
    }

    /// Output-clock time of the first maximum-depth sample in a one-based repetition.
    static func maximumHipDropOutputTime(rep: Int, motion: ArmMotion, mutations: [MovementMutation],
                                         readyHold: TimeInterval) -> TimeInterval {
        guard (1...MovementScenario.maximumReps).contains(rep),
              let pauses = MovementSequenceDurations.pauseSegments(in: mutations) else { return .nan }
        var repStart = readyHold
        if rep > 1 {
            for precedingRep in 1..<rep {
                guard let duration = MovementSequenceDurations.repetitionDuration(
                    for: precedingRep, motionDuration: motion.duration, mutations: mutations
                ), let next = MovementSequenceDurations.adding(duration, to: repStart) else {
                    return .nan
                }
                repStart = next
            }
        }
        guard let scale = MovementSequenceDurations.tempoScale(for: rep, mutations: mutations) else { return .nan }
        guard let preInsertionPeak = MovementSequenceDurations.adding(
            maximumHipDropTime(in: motion) * scale, to: repStart
        ) else { return .nan }
        var outputPeak = preInsertionPeak
        for pause in pauses where pause.at < preInsertionPeak {
            guard let next = MovementSequenceDurations.adding(pause.duration, to: outputPeak) else { return .nan }
            outputPeak = next
        }
        return outputPeak
    }
}

/// SplitMix64 gives the test target stable jitter without a platform RNG dependency.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func signedUnit() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        let unit = Double(value >> 11) / 9_007_199_254_740_992.0
        return unit * 2 - 1
    }
}
