import CoreGraphics
import Foundation
import XCTest
@testable import PostureAnalysisApp

final class RearLungeAnalyzerTests: XCTestCase {
    private let exercise = RearLungeExercise.definition()
    private var motion: ArmMotion { exercise.guide.motion }

    func testGuideCountsOncePerLoopAcrossScaleFacingAndSegmentProportions() throws {
        let variants: [(CGFloat, CGFloat, CGFloat, Bool)] = [
            (0.5, 1, 1, false), (2, 1, 1, true),
            (1, 0.85, 1, true), (1, 1.15, 1, false),
            (1, 1, 0.85, false), (1, 1, 1.15, true)
        ]

        for (scale, thigh, shin, mirrored) in variants {
            let result = try run(motion, loops: 2, scale: scale, thigh: thigh, shin: shin,
                                 mirrored: mirrored)
            let label = "scale \(scale), thigh \(thigh), shin \(shin), mirrored \(mirrored)"
            XCTAssertEqual(result.reps, 2, label)
            if thigh == 1, shin == 1 {
                XCTAssertTrue(result.forms.allSatisfy { $0.flags.isEmpty },
                              "The demonstration raises no cues: \(result.forms)")
                XCTAssertTrue(result.signals.allSatisfy(\.isEmpty), label)
            }
        }

        XCTAssertEqual(try measuredDrop(motion.startSample), 0, accuracy: 0.001)
        XCTAssertEqual(try measuredDrop(motion.topSample), 0.38, accuracy: 0.01)
    }

    func testEightGuideRepsAndNearStandReturnsKeepTheBaselineStable() throws {
        XCTAssertEqual(try run(motion, loops: 8).reps, 8)

        let analyzer = RearLungeAnalyzer(epoch: 1)
        var time: TimeInterval = 0
        var reps = 0
        func sample(_ drop: Double) throws {
            reps += analyzer.process(try frame(drop: drop, time: time), counting: true).repEvents.count
            time += 0.1
        }

        try sample(0)
        try sample(0)
        for _ in 0..<6 {
            for _ in 0..<12 { try sample(0.38) }
            try sample(0.07)
            try sample(0.07)
        }
        XCTAssertEqual(reps, 6, "Every full-depth rep counts after a return that stops at H + 0.07 L.")

        try sample(0)
        try sample(0)
        XCTAssertEqual(reps, 6, "A full return to H does not create a rep by itself.")

        for _ in 0..<12 { try sample(0.38) }
        try sample(0.07)
        try sample(0.07)
        XCTAssertEqual(reps, 7, "A full-depth rep still counts after the full return to H.")

        for _ in 0..<12 { try sample(0.38) }
        try sample(0.14)
        try sample(0.14)
        XCTAssertEqual(reps, 7, "A progressively lower return cannot ratchet the standing baseline down.")

        try sample(0)
        try sample(0)
        XCTAssertEqual(reps, 8, "The lower return only completes once the user reaches H.")

        for _ in 0..<12 { try sample(0.38) }
        try sample(0)
        try sample(0)
        XCTAssertEqual(reps, 9, "Standing fully again lets the next complete rep count.")
    }

    func testShallowLungeAsksForMoreDepth() throws {
        let result = try run(motionWithLunge(drop: 0.2))

        XCTAssertEqual(result.reps, 0)
        XCTAssertTrue(result.forms.contains { $0.flags.contains(.lungeDeeper) })
    }

    func testShortStepAsksForMoreDistanceOnlyWhenBothAnklesAreVisible() throws {
        let shortStep = motionWithLunge(stride: 0.4)
        let visible = try run(shortStep)
        let hiddenRearAnkle = try run(shortStep, hidesRearAnkle: true)

        XCTAssertTrue(visible.forms.contains { $0.flags.contains(.lungeStepLonger) })
        XCTAssertFalse(hiddenRearAnkle.forms.contains { $0.flags.contains(.lungeStepLonger) })
        XCTAssertEqual(hiddenRearAnkle.reps, 1, "The second ankle is optional for counting.")
    }

    func testEstimatedAnkleStillCountsWithoutFormFlagsOrSignals() throws {
        let result = try run(motionWithLunge(stride: 0.4), estimatedJoints: [.leftAnkle])

        XCTAssertEqual(result.reps, 1)
        XCTAssertTrue(result.forms.allSatisfy { $0.flags.isEmpty }, "\(result.forms)")
        XCTAssertTrue(result.signals.allSatisfy(\.isEmpty), "\(result.signals)")
    }

    func testReloweringWithoutStandingAsksToStandTall() throws {
        let arms = ArmAngles(upperArmElevation: -90, forearmElevation: -90)
        let motion = ArmMotion(keyframes: [
            ArmKeyframe(angles: arms, moveDuration: 0, holdDuration: 1, stepIndex: 0),
            ArmKeyframe(angles: arms, moveDuration: 1.5, holdDuration: 0.2, stepIndex: 1,
                        shape: FigureShape(torsoPitch: 0, hipShift: 1, hipDrop: 0.5, stride: 1.1)),
            ArmKeyframe(angles: arms, moveDuration: 0.6, holdDuration: 0.2, stepIndex: 1,
                        shape: FigureShape(torsoPitch: 0, hipShift: 0.7, hipDrop: 0.35, stride: 0.8)),
            ArmKeyframe(angles: arms, moveDuration: 0.6, holdDuration: 0.2, stepIndex: 1,
                        shape: FigureShape(torsoPitch: 0, hipShift: 1, hipDrop: 0.5, stride: 1.1)),
            ArmKeyframe(angles: arms, moveDuration: 1.5, holdDuration: 0, stepIndex: 2)
        ])
        let result = try run(motion)

        XCTAssertEqual(result.reps, 1)
        XCTAssertTrue(result.forms.contains { $0.flags.contains(.lungeStandTall) }, "\(result.forms)")
    }

    func testForwardLeanRaisesChestUpCue() throws {
        let result = try run(motionWithLunge(torsoPitch: 30))

        XCTAssertEqual(result.reps, 1)
        XCTAssertTrue(result.signals.contains { $0.contains(.lungeChestUp) })
    }

    func testTrackingGapInvalidatesTheCycle() throws {
        XCTAssertEqual(try run(motion, gapAfter: 2.0).reps, 0)
    }

    func testGapAndSideSwitchClearTheReferenceAtBothScales() throws {
        for scale in [CGFloat(1), 0.8] {
            for switchSide in [false, true] {
                let reps = try runInterruptedRepAndRecovery(scale: scale, switchingSide: switchSide)
                XCTAssertEqual(reps, 1,
                               "scale \(scale), side switch \(switchSide): interrupted rep is rejected, next rep counts")
            }
        }
    }

    func testStandAndLungeBoundariesNeedTwoConsecutiveSamples() throws {
        let atStand = RearLungeAnalyzer(epoch: 1)
        _ = atStand.process(try frame(drop: 0, time: 0), counting: true)
        _ = atStand.process(try frame(drop: 0, time: 0.1), counting: true)
        _ = atStand.process(try frame(drop: 0.30, time: 0.2), counting: true)
        _ = atStand.process(try frame(drop: 0.30, time: 0.3), counting: true)
        XCTAssertFalse(atStand.process(try frame(drop: 0.08, time: 0.4), counting: true).startPositionHeld)
        XCTAssertTrue(atStand.process(try frame(drop: 0.08, time: 0.5), counting: true).startPositionHeld)

        let aboveStand = RearLungeAnalyzer(epoch: 1)
        _ = aboveStand.process(try frame(drop: 0, time: 0), counting: true)
        _ = aboveStand.process(try frame(drop: 0, time: 0.1), counting: true)
        _ = aboveStand.process(try frame(drop: 0.30, time: 0.2), counting: true)
        _ = aboveStand.process(try frame(drop: 0.30, time: 0.3), counting: true)
        XCTAssertFalse(aboveStand.process(try frame(drop: 0.09, time: 0.4), counting: true).startPositionHeld)
        XCTAssertFalse(aboveStand.process(try frame(drop: 0.09, time: 0.5), counting: true).startPositionHeld)

        let belowLunge = RearLungeAnalyzer(epoch: 1)
        _ = belowLunge.process(try frame(drop: 0, time: 0), counting: true)
        _ = belowLunge.process(try frame(drop: 0, time: 0.1), counting: true)
        XCTAssertTrue(belowLunge.process(try frame(drop: 0.29, time: 0.2), counting: true).endPositionSides.isEmpty)
        XCTAssertTrue(belowLunge.process(try frame(drop: 0.29, time: 0.3), counting: true).endPositionSides.isEmpty)

        let atLunge = RearLungeAnalyzer(epoch: 1)
        _ = atLunge.process(try frame(drop: 0, time: 0), counting: true)
        _ = atLunge.process(try frame(drop: 0, time: 0.1), counting: true)
        XCTAssertTrue(atLunge.process(try frame(drop: 0.30, time: 0.2), counting: true).endPositionSides.isEmpty)
        XCTAssertEqual(atLunge.process(try frame(drop: 0.30, time: 0.3), counting: true).endPositionSides, [.left])
    }

    func testThresholdLinesUseTheLockedStandingHipAndLegLength() throws {
        let result = try run(motion)
        let stand = try XCTUnwrap(result.lockedStandThresholds)
        let lunge = try XCTUnwrap(result.lungeThresholds)

        XCTAssertEqual(stand.startLine.label, "Stand ↑")
        XCTAssertEqual(stand.topLine.label, "Lunge ↓")
        XCTAssertEqual(stand.startLine, lunge.startLine)
        XCTAssertEqual(stand.topLine, lunge.topLine)
        let expectedWidth = 0.7 * (try measuredLegLength(motion.startSample))
        XCTAssertEqual(stand.startLine.to.x - stand.startLine.from.x, expectedWidth, accuracy: 0.01)
    }

    func testDefinitionUsesSideOnFramingAndPerLegTargets() throws {
        XCTAssertEqual(exercise.id.rawValue, "rear_lunge")
        XCTAssertEqual(exercise.sets, 2)
        XCTAssertEqual(exercise.targetReps, 8...8)
        XCTAssertEqual(exercise.autoCompleteReps, 8)
        XCTAssertEqual(exercise.restSeconds, 60)
        XCTAssertTrue(exercise.perSide)
        XCTAssertEqual(exercise.sideLimb, .leg)
        XCTAssertEqual(exercise.setsAndRepsLabel, "2 sets × 8 reps each leg")
        XCTAssertEqual(exercise.perSideTargetSuffix, " each leg")
        XCTAssertEqual(exercise.setLabel(entry: 0), "Set 1 L")
        XCTAssertEqual(exercise.setLabel(entry: 1), "Set 1 R")
        XCTAssertEqual(exercise.requiredJoints, [])
        XCTAssertEqual(exercise.anyOfRequiredJoints, [
            [.leftShoulder, .leftHip, .leftKnee, .leftAnkle],
            [.rightShoulder, .rightHip, .rightKnee, .rightAnkle]
        ])
        XCTAssertEqual(exercise.cameraView, .side)
        XCTAssertFalse(exercise.startsByHolding)
        XCTAssertEqual(exercise.guide.startPositionInstruction, "Stand tall, dumbbells at your sides")
        XCTAssertTrue(exercise.plantedJoints.isEmpty)

        let parser = VoiceCommandParser(exercises: ExerciseCatalog.all)
        for alias in exercise.voiceAliases {
            XCTAssertEqual(parser.parse(alias)?.command, .selectExercise(.rearLunge), alias)
        }
        let photo = try XCTUnwrap(ExercisePhotography.photograph(for: .rearLunge))
        XCTAssertEqual(photo.exerciseName, "Dumbbell Rear Lunge")
        XCTAssertEqual(photo.assetName, "ExerciseThumbnails/rear_lunge")
        XCTAssertEqual(photo.photographer, "Anna Shvets")
        XCTAssertEqual(photo.source, "Pexels")
        XCTAssertEqual(photo.sourceURL.absoluteString,
                       "https://www.pexels.com/photo/senior-man-doing-sport-exercises-5067741/")
        XCTAssertEqual(photo.license, "Pexels License")
    }

    func testFramingAcceptsEitherCompleteSideWithoutRequiringBothLegs() throws {
        var framing = FramingEvaluator(requiredJoints: exercise.requiredJoints,
                                       anyOfRequiredJoints: exercise.anyOfRequiredJoints,
                                       headroomArmLengths: exercise.headroomArmLengths,
                                       cameraView: exercise.cameraView)
        var pose = mirror(try demoPose(motion.startSample))
        pose[.leftAnkle] = nil
        pose[.leftKnee] = nil
        pose = pose.mapValues { CGPoint(x: $0.x + 390, y: $0.y + 400) }
        var status = FramingStatus.lost
        for index in 0...6 {
            status = framing.evaluate(try frame(joints: pose, time: Double(index) / 10))
        }

        XCTAssertTrue(status.isReliable)
        XCTAssertNil(status.guidance)
    }

    private struct Run {
        var reps = 0
        var forms: [RepForm] = []
        var signals: [Set<CoachingCueID>] = []
        var lockedStandThresholds: ArmThresholds?
        var lungeThresholds: ArmThresholds?
    }

    private func run(_ motion: ArmMotion, loops: Int = 1, scale: CGFloat = 1,
                     thigh: CGFloat = 1, shin: CGFloat = 1, mirrored: Bool = false,
                     hidesRearAnkle: Bool = false, gapAfter: TimeInterval? = nil,
                     estimatedJoints: Set<LandmarkType> = []) throws -> Run {
        let analyzer = RearLungeAnalyzer(epoch: 1)
        var result = Run()
        let sampleCount = Int(motion.duration * Double(loops) * 10)
        var timestampOffset: TimeInterval = 0
        for index in 0..<sampleCount {
            let motionTime = Double(index) / 10
            if let gapAfter, motionTime >= gapAfter, timestampOffset == 0 { timestampOffset = 0.4 }
            let sample = motion.sample(at: motionTime)
            var joints = try demoPose(sample)
            adjust(joints: &joints, sample: sample, thigh: thigh, shin: shin,
                   hidesRearAnkle: hidesRearAnkle)
            if mirrored { joints = mirror(joints) }
            joints = joints.mapValues { CGPoint(x: $0.x * scale + 300, y: $0.y * scale + 400) }

            let analysis = analyzer.process(try frame(joints: joints, time: motionTime + timestampOffset,
                                                      estimatedJoints: estimatedJoints), counting: true)
            result.reps += analysis.repEvents.count
            result.forms += analysis.repForms
            result.signals.append(analysis.formSignals)
            if let thresholds = analysis.thresholds[.left], thresholds.isLocked {
                if sample.shape.hipDrop >= 0.3 {
                    result.lungeThresholds = thresholds
                } else if result.lungeThresholds == nil, sample.shape.hipDrop <= 0.08 {
                    result.lockedStandThresholds = thresholds
                }
            }
        }
        return result
    }

    private func motionWithLunge(drop: Double = 0.5, stride: Double = 1.1,
                                 torsoPitch: Double = 0) -> ArmMotion {
        let arms = ArmAngles(upperArmElevation: -90, forearmElevation: -90)
        return ArmMotion(keyframes: [
            ArmKeyframe(angles: arms, moveDuration: 0, holdDuration: 1, stepIndex: 0),
            ArmKeyframe(angles: arms, moveDuration: 1.5, holdDuration: 0.4, stepIndex: 1,
                        shape: FigureShape(torsoPitch: torsoPitch, hipShift: drop == 0.2 ? 0.4 : 1,
                                           hipDrop: drop, stride: stride)),
            ArmKeyframe(angles: arms, moveDuration: 1.5, holdDuration: 0, stepIndex: 2)
        ])
    }

    private func measuredDrop(_ sample: ArmMotionSample) throws -> Double {
        let standing = try demoPose(motion.startSample)
        let pose = try demoPose(sample)
        let startHip = try XCTUnwrap(standing[.leftHip])
        let sampleHip = try XCTUnwrap(pose[.leftHip])
        let legLength = try measuredLegLength(motion.startSample)
        return Double((sampleHip.y - startHip.y) / legLength)
    }

    private func measuredLegLength(_ sample: ArmMotionSample) throws -> CGFloat {
        let joints = try demoPose(sample)
        let hip = try XCTUnwrap(joints[.leftHip])
        let knee = try XCTUnwrap(joints[.leftKnee])
        let ankle = try XCTUnwrap(joints[.leftAnkle])
        return ArmGeometry.distance(hip, knee) + ArmGeometry.distance(knee, ankle)
    }

    private func adjust(joints: inout [LandmarkType: CGPoint], sample: ArmMotionSample,
                        thigh: CGFloat, shin: CGFloat, hidesRearAnkle: Bool) {
        guard let hip = joints[.leftHip], let ankle = joints[.leftAnkle] else { return }
        let standing = ExerciseDemoFigureView.sideFigureJoints
        let baseThigh = ArmGeometry.distance(standing[.leftHip] ?? .zero, standing[.leftKnee] ?? .zero)
        let baseShin = ArmGeometry.distance(standing[.leftKnee] ?? .zero, standing[.leftAnkle] ?? .zero)
        joints[.leftKnee] = ArmGeometry.twoBoneKnee(hip: hip, ankle: ankle,
                                                   thighLength: baseThigh * thigh,
                                                   shinLength: baseShin * shin,
                                                   bendDirection: 1)
        if hidesRearAnkle { joints[.rightAnkle] = nil }
    }

    private func demoPose(_ sample: ArmMotionSample) throws -> [LandmarkType: CGPoint] {
        ExerciseDemoFigureView.pose(for: sample, cameraView: .side).jointLocations
    }

    private func mirror(_ joints: [LandmarkType: CGPoint]) -> [LandmarkType: CGPoint] {
        Dictionary(uniqueKeysWithValues: joints.map { landmark, point in
            (oppositeSide(of: landmark) ?? landmark,
             CGPoint(x: ExerciseDemoFigureView.canvasSize.width - point.x, y: point.y))
        })
    }

    private func oppositeSide(of landmark: LandmarkType) -> LandmarkType? {
        guard let side = BodySide.side(of: landmark) else { return nil }
        let other: BodySide = side == .left ? .right : .left
        if landmark == side.shoulder { return other.shoulder }
        if landmark == side.elbow { return other.elbow }
        if landmark == side.wrist { return other.wrist }
        if landmark == side.hip { return other.hip }
        if landmark == side.knee { return other.knee }
        if landmark == side.ankle { return other.ankle }
        return nil
    }

    private func frame(drop: Double, time: TimeInterval, scale: CGFloat = 1,
                       xOffset: CGFloat = 0, yOffset: CGFloat = 0,
                       hipOffset: CGFloat = 0, side: BodySide = .left,
                       estimatedJoints: Set<LandmarkType> = []) throws -> PoseFrame {
        let sample = ArmMotionSample(angles: motion.startAngles, stepIndex: 0,
                                     shape: FigureShape(torsoPitch: 0, hipShift: 0,
                                                        hipDrop: drop, stride: 0))
        return try frame(joints: demoPose(sample), time: time, scale: scale, xOffset: xOffset, yOffset: yOffset,
                         hipOffset: hipOffset, side: side, estimatedJoints: estimatedJoints)
    }

    private func frame(joints: [LandmarkType: CGPoint], time: TimeInterval,
                       scale: CGFloat = 1, xOffset: CGFloat = 0, yOffset: CGFloat = 0,
                       hipOffset: CGFloat = 0,
                       side: BodySide = .left,
                       estimatedJoints: Set<LandmarkType> = []) throws -> PoseFrame {
        let mappedJoints = side == .left ? joints : mirror(joints)
        let landmarks = Dictionary(uniqueKeysWithValues: mappedJoints.map { type, point in
            (type, Landmark(type: type, normalizedLocation: .zero,
                            imageLocation: CGPoint(x: point.x * scale + xOffset,
                                                  y: point.y * scale + yOffset + hipOffset),
                            confidence: 0.9))
        })
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920),
                         timestamp: time, estimatedJoints: estimatedJoints)
    }

    private func runInterruptedRepAndRecovery(scale: CGFloat, switchingSide: Bool) throws -> Int {
        let analyzer = RearLungeAnalyzer(epoch: 1)
        let legLength = try measuredLegLength(motion.startSample) * scale
        var reps = 0
        func sample(_ drop: Double, at time: TimeInterval, side: BodySide,
                    hipOffset: CGFloat = 0) throws {
            let frame = try frame(drop: drop, time: time, scale: scale,
                                  xOffset: 300, yOffset: 400, hipOffset: hipOffset, side: side)
            reps += analyzer.process(frame, counting: true).repEvents.count
        }

        try sample(0, at: 0, side: .left)
        try sample(0, at: 0.1, side: .left)
        try sample(0.38, at: 0.2, side: .left)
        try sample(0.38, at: 0.3, side: .left)

        let recoveredSide: BodySide = switchingSide ? .right : .left
        let firstRecoveryTime: TimeInterval = switchingSide ? 0.4 : 1.0
        let translation = legLength * 0.25
        try sample(0, at: firstRecoveryTime, side: recoveredSide, hipOffset: translation)
        try sample(0, at: firstRecoveryTime + 0.1, side: recoveredSide, hipOffset: translation)
        for index in 0..<12 {
            try sample(0.38, at: firstRecoveryTime + 0.2 + Double(index) * 0.1,
                       side: recoveredSide, hipOffset: translation)
        }
        try sample(0, at: firstRecoveryTime + 1.4, side: recoveredSide, hipOffset: translation)
        try sample(0, at: firstRecoveryTime + 1.5, side: recoveredSide, hipOffset: translation)
        return reps
    }
}
