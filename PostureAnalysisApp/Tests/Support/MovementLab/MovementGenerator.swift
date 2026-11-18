import CoreGraphics
import Foundation
@testable import PostureAnalysisApp

/// One synchronized canonical and modified sample on the scenario timeline.
struct MovementMaterializedFrame {
    let frame: PoseFrame
    /// Unmodified guide pose for the synchronized reference view.
    let referenceFrame: PoseFrame
    /// Guide pose after structural range mutations; constrained edits preserve these lengths.
    let constraintReferenceFrame: PoseFrame
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
    static let minimumCompositeDepthScale = 1.0 / 16.0
    static let maximumCompositeDepthScale = 16.0

    private struct RepSegment {
        var rep: Int
        var start: TimeInterval
        var duration: TimeInterval
        var tempoScale: Double
    }

    private struct TurnSegment {
        var at: TimeInterval
        var duration: TimeInterval
        var toView: ExerciseCameraView
    }

    private struct RenderedGuide {
        var locations: [LandmarkType: CGPoint]
        var cameraView: ExerciseCameraView
    }

    static func materialize(plan: MovementPlan, scenario: MovementScenario,
                            startingTimestamp: TimeInterval = 0) -> MovementMaterialization {
        var invalidReasons = scenario.validate().map(\.message)
        guard let base = ExerciseCatalog.all.first(where: { $0.id == scenario.exercise }) else {
            return invalid(["Unknown exercise \(scenario.exercise.rawValue)."])
        }
        // Everything below renders and measures the scenario's camera view.
        let exercise = base.inView(scenario.cameraView)
        let expectedRevision = MovementCanonicalRevision.value(for: exercise)
        guard scenario.canonicalRevision == expectedRevision else {
            invalidReasons.append(
                "The canonical exercise guide changed; refresh canonicalRevision to \(expectedRevision) before materializing."
            )
            return invalid(invalidReasons)
        }
        guard startingTimestamp.isFinite else {
            return invalid(["startingTimestamp must be finite."])
        }
        guard MovementISO8601.date(from: plan.createdAt) != nil else {
            return invalid(["createdAt must be a valid ISO 8601 date-time."])
        }
        guard invalidReasons.isEmpty else { return invalid(invalidReasons) }

        if let reason = compositeDepthScaleError(for: scenario) {
            return invalid([reason])
        }

        if scenario.mode == .constrained {
            for mutation in scenario.mutations {
                guard case .jointOffset(_, let dx, let dy, _, _, _, let strength) = mutation else { continue }
                if hypot(dx, dy) * strength > 0.3 {
                    return invalid(["Constrained projection cannot satisfy a joint offset larger than 0.3 body-heights."])
                }
            }
        }

        let motion = scenario.exercise == .pushUp ? PushUpMovement.motion : exercise.guide.motion
        let turns = scenario.mutations.compactMap { mutation -> TurnSegment? in
            guard case .turn(let at, let duration, let toView) = mutation else { return nil }
            return TurnSegment(at: at, duration: duration, toView: toView)
        }
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

            let referenceFrame: PoseFrame
            if turns.isEmpty && scenario.exercise == .pushUp {
                let referenceLocations = ExerciseDemoFigureView.pose(
                    for: motion.sample(at: motionTime), forearmPlane: motion.forearmPlane,
                    cameraView: exercise.cameraView
                ).jointLocations
                let referencePose = ReadyPoseFixtures.pose(for: Set(referenceLocations.keys),
                                                            reference: referenceLocations, exercise: exercise)
                referenceFrame = PoseFrame(pose: referencePose, timestamp: startingTimestamp + elapsed)
            } else if turns.isEmpty {
                referenceFrame = ReadyPoseFixtures.demoFrame(exercise, motionTime: motionTime,
                                                              at: startingTimestamp + elapsed)
            } else {
                let referenceGuide = renderedGuide(for: motion.sample(at: motionTime), base: base,
                                                   startingView: scenario.cameraView, turns: turns, at: elapsed)
                let referenceExercise = base.inView(referenceGuide.cameraView)
                let referencePose = ReadyPoseFixtures.pose(for: Set(referenceGuide.locations.keys),
                                                            reference: referenceGuide.locations,
                                                            exercise: referenceExercise)
                referenceFrame = PoseFrame(pose: referencePose, timestamp: startingTimestamp + elapsed)
            }
            var renderedSample = motion.sample(at: motionTime)
            for mutation in scenario.mutations {
                guard case .depthScale(let scale, let selectedReps) = mutation,
                      let repIndex, selectedReps == nil || selectedReps?.contains(repIndex) == true else { continue }
                if scenario.exercise == .pushUp {
                    renderedSample = PushUpMovement.applyingDepthScale(to: renderedSample, scale: scale)
                } else {
                    renderedSample.legs.hipDrop *= scale
                    guard renderedSample.legs.hipDrop.isFinite else {
                        return invalid(["Depth-scaled guide geometry is not finite at repetition \(repIndex ?? 0)."])
                    }
                }
            }
            let renderedLocations: [LandmarkType: CGPoint]
            let renderedExercise: ExerciseDefinition
            if turns.isEmpty {
                renderedLocations = ExerciseDemoFigureView.pose(
                    for: renderedSample, forearmPlane: motion.forearmPlane, cameraView: exercise.cameraView
                ).jointLocations
                renderedExercise = exercise
            } else {
                let guide = renderedGuide(for: renderedSample, base: base, startingView: scenario.cameraView,
                                          turns: turns, at: elapsed)
                renderedLocations = guide.locations
                renderedExercise = base.inView(guide.cameraView)
            }
            guard renderedLocations.values.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
                return invalid(["Rendered guide coordinates must be finite."])
            }
            let renderedPose = ReadyPoseFixtures.pose(for: Set(renderedLocations.keys), reference: renderedLocations,
                                                       exercise: renderedExercise)
            let renderedFrame = PoseFrame(pose: renderedPose, timestamp: startingTimestamp + elapsed)
            let guidePoints = coordinates(in: renderedFrame.pose)
            guard pointsAreFinite(guidePoints) else {
                return invalid(["Rendered guide coordinates must be finite."])
            }
            var points = guidePoints
            let bodyHeight = max(1, bodyHeight(of: points))
            guard bodyHeight.isFinite else { return invalid(["Rendered body height must be finite."]) }
            let plantedJoints = renderedExercise.plantedJoints
            var targetJoints = Set<LandmarkType>()
            var exactTargetJoints = Set<LandmarkType>()

            // 1. Seeded pixel jitter is bounded to 0.002 body-heights per axis.
            for joint in LandmarkType.allCases where points[joint] != nil {
                guard let point = points[joint] else { continue }
                let jitterX = CGFloat(random.signedUnit() * 0.002 * bodyHeight)
                let jitterY = CGFloat(random.signedUnit() * 0.002 * bodyHeight)
                points[joint] = CGPoint(x: point.x + jitterX, y: point.y + jitterY)
            }

            // 2. Asymmetry follows the rendered squat depth so standing stays level.
            let depthRatio = min(1, max(0, renderedSample.legs.hipDrop / max(0.001, motion.topLegs.hipDrop)))
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

            guard pointsAreFinite(points) else {
                return invalid(["Mutated guide coordinates must remain finite before projection."])
            }

            // 4. Constrained edits project onto the rendered pose's bone lengths and keep its planted joints fixed.
            if scenario.mode == .constrained {
                let requestedPoints = points
                for joint in orderedLandmarks(in: plantedJoints) {
                    if targetJoints.contains(joint), let requested = requestedPoints[joint],
                       let planted = guidePoints[joint], ArmGeometry.distance(requested, planted) > 0.01 {
                        return invalid(["Constrained projection cannot move planted landmark \(joint.rawValue)."])
                    }
                    if let planted = guidePoints[joint] { points[joint] = planted }
                }
                if let reason = constrain(&points, reference: guidePoints, requested: requestedPoints,
                                          planted: plantedJoints, targetJoints: targetJoints,
                                          exactTargetJoints: exactTargetJoints) {
                    invalidReasons.append(reason)
                    return invalid(invalidReasons)
                }
            }

            guard pointsAreFinite(points) else {
                return invalid(["Projected guide coordinates must remain finite."])
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
            guard pointsAreFinite(points) else {
                return invalid(["Framed guide coordinates must remain finite."])
            }
            for (joint, point) in Array(points) where point.x < 0 || point.x >= imageSize.width
                || point.y < 0 || point.y >= imageSize.height {
                points.removeValue(forKey: joint)
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

            var pose = renderedFrame.pose
            for joint in LandmarkType.allCases {
                guard var landmark = pose[joint] else { continue }
                guard let point = points[joint] else {
                    pose[joint] = nil
                    continue
                }
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
                                                          constraintReferenceFrame: renderedFrame, elapsed: elapsed))
        }

        let lines = MovementMaterializer.recordingLines(plan: plan, scenario: scenario, exercise: base,
                                                        frames: outputFrames)
        return MovementMaterialization(frames: outputFrames, recordingLines: lines, invalidReasons: [])
    }

    private static func invalid(_ reasons: [String]) -> MovementMaterialization {
        MovementMaterialization(frames: [], recordingLines: [], invalidReasons: reasons)
    }

    /// Renders the current guide view, blending a turn's two poses on the same motion sample.
    private static func renderedGuide(for sample: ArmMotionSample, base: ExerciseDefinition,
                                      startingView: ExerciseCameraView, turns: [TurnSegment],
                                      at elapsed: TimeInterval) -> RenderedGuide {
        var activeView = startingView
        for turn in turns {
            guard elapsed >= turn.at else { break }
            let end = turn.at + turn.duration
            guard elapsed < end else {
                activeView = turn.toView
                continue
            }

            let sourceExercise = base.inView(activeView)
            let targetExercise = base.inView(turn.toView)
            let source = guideLocations(for: sample, in: sourceExercise)
            let target = guideLocations(for: sample, in: targetExercise)
            let progress = min(1, max(0, (elapsed - turn.at) / turn.duration))
            return RenderedGuide(locations: blendedLocations(from: source, to: target, progress: progress),
                                 cameraView: progress < 0.5 ? activeView : turn.toView)
        }

        let exercise = base.inView(activeView)
        return RenderedGuide(locations: guideLocations(for: sample, in: exercise), cameraView: activeView)
    }

    private static func guideLocations(for sample: ArmMotionSample,
                                       in exercise: ExerciseDefinition) -> [LandmarkType: CGPoint] {
        ExerciseDemoFigureView.pose(for: sample, forearmPlane: exercise.guide.motion.forearmPlane,
                                    cameraView: exercise.cameraView).jointLocations
    }

    /// Shared joints glide with smoothstep. View-only joints swap at the midpoint; paired far-side joints converge
    /// onto the visible side before disappearing, so shoulder-width readings pass through the unclear band.
    private static func blendedLocations(from source: [LandmarkType: CGPoint], to target: [LandmarkType: CGPoint],
                                         progress: Double) -> [LandmarkType: CGPoint] {
        let weight = smoothstep(progress)
        var result: [LandmarkType: CGPoint] = [:]
        for joint in LandmarkType.allCases {
            switch (source[joint], target[joint]) {
            case let (.some(sourcePoint), .some(targetPoint)):
                result[joint] = interpolate(sourcePoint, targetPoint, weight: weight)
            case let (.some(sourcePoint), .none):
                guard progress < 0.5 else { continue }
                let destination = oppositeLandmark(joint).flatMap { target[$0] } ?? sourcePoint
                result[joint] = interpolate(sourcePoint, destination, weight: weight)
            case let (.none, .some(targetPoint)):
                guard progress >= 0.5 else { continue }
                let sourcePoint = oppositeLandmark(joint).flatMap { source[$0] } ?? targetPoint
                let revealProgress = smoothstep(min(1, max(0, (progress - 0.5) * 2)))
                result[joint] = interpolate(sourcePoint, targetPoint, weight: revealProgress)
            case (.none, .none):
                continue
            }
        }
        return result
    }

    private static func smoothstep(_ progress: Double) -> Double {
        let value = min(1, max(0, progress))
        return value * value * (3 - 2 * value)
    }

    private static func interpolate(_ from: CGPoint, _ to: CGPoint, weight: Double) -> CGPoint {
        let fraction = CGFloat(weight)
        return CGPoint(x: from.x + (to.x - from.x) * fraction,
                       y: from.y + (to.y - from.y) * fraction)
    }

    private static func oppositeLandmark(_ joint: LandmarkType) -> LandmarkType? {
        switch joint {
        case .leftEye: return .rightEye
        case .rightEye: return .leftEye
        case .leftEar: return .rightEar
        case .rightEar: return .leftEar
        case .leftShoulder: return .rightShoulder
        case .rightShoulder: return .leftShoulder
        case .leftElbow: return .rightElbow
        case .rightElbow: return .leftElbow
        case .leftWrist: return .rightWrist
        case .rightWrist: return .leftWrist
        case .leftHip: return .rightHip
        case .rightHip: return .leftHip
        case .leftKnee: return .rightKnee
        case .rightKnee: return .leftKnee
        case .leftAnkle: return .rightAnkle
        case .rightAnkle: return .leftAnkle
        case .nose, .neck, .root: return nil
        }
    }

    private static func compositeDepthScaleError(for scenario: MovementScenario) -> String? {
        for rep in 1...scenario.reps {
            var scale = 1.0
            for (index, mutation) in scenario.mutations.enumerated() {
                guard case .depthScale(let factor, let selectedReps) = mutation,
                      selectedReps == nil || selectedReps?.contains(rep) == true else { continue }
                scale *= factor
                guard scale.isFinite, scale >= minimumCompositeDepthScale,
                      scale <= maximumCompositeDepthScale else {
                    return "Composite depth scale after mutation \(index) for repetition \(rep) must stay between 0.0625 and 16."
                }
            }
        }
        return nil
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

    private static func pointsAreFinite(_ points: [LandmarkType: CGPoint]) -> Bool {
        points.values.allSatisfy { $0.x.isFinite && $0.y.isFinite }
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
                                  exactTargetJoints: Set<LandmarkType>) -> String? {
        guard pointsAreFinite(points), pointsAreFinite(reference), pointsAreFinite(requested) else {
            return "Constrained projection received nonfinite coordinates."
        }
        for _ in 0..<80 {
            for (first, second) in BodyPose.connections {
                guard let referenceFirst = reference[first], let referenceSecond = reference[second],
                      let firstPoint = points[first], let secondPoint = points[second] else { continue }
                let targetLength = ArmGeometry.distance(referenceFirst, referenceSecond)
                guard targetLength.isFinite else { return "Constrained projection received a nonfinite guide bone length." }
                guard targetLength > 0.000_1 else { continue }
                let dx = secondPoint.x - firstPoint.x
                let dy = secondPoint.y - firstPoint.y
                let length = hypot(dx, dy)
                guard length > 0.000_1 else { continue }
                let error = length - targetLength
                let firstWeight: CGFloat = planted.contains(first) || exactTargetJoints.contains(first) ? 0
                    : (targetJoints.contains(first) ? 0.05 : 1)
                let secondWeight: CGFloat = planted.contains(second) || exactTargetJoints.contains(second) ? 0
                    : (targetJoints.contains(second) ? 0.05 : 1)
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
            guard difference.isFinite else { return "Constrained projection produced a nonfinite bone length." }
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
    /// `exercise` is the catalog definition the header describes; the exercise control selects the scenario's view.
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
        lines.append(WorkoutSessionLines.control(.exercise(exercise.inView(scenario.cameraView), analyzerEpoch: 1),
                                                 t: 0).serialized)
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

    static func recordingID(plan: MovementPlan, scenario: MovementScenario) -> UUID {
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
        value(for: exercise.id, motion: exercise.guide.motion,
              cameraView: exercise.cameraView == exercise.usualView ? nil : exercise.cameraView)
    }

    /// `cameraView` is hashed only when given, for a view other than the usual one, so every hash made before
    /// exercises had more than one view stays the same.
    static func value(for exercise: ExerciseID, motion: ArmMotion, cameraView: ExerciseCameraView? = nil) -> String {
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
        if let cameraView { fields.append("view:\(cameraView.rawValue)") }
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
