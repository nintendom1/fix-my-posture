import CoreGraphics
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class DumbbellShrugAnalyzerTests: XCTestCase {
    private let exercise = DumbbellShrugExercise.definition()
    private var motion: ArmMotion { exercise.guide.motion }
    /// The guide figure's shoulder width in canvas units.
    private var figureShoulderWidth: CGFloat {
        let left = ExerciseDemoFigureView.figureJoints[.leftShoulder] ?? .zero
        let right = ExerciseDemoFigureView.figureJoints[.rightShoulder] ?? .zero
        return ArmGeometry.distance(left, right)
    }

    func testGuideDemonstrationCountsOneRepPerLoopMeasuresRestAndTopAndRaisesNoCues() throws {
        let result = run(motion)
        XCTAssertEqual(result.reps, 3)
        XCTAssertEqual(result.repSides, Array(repeating: Set(BodySide.allCases), count: 3))
        XCTAssertEqual(result.forms.count, 3, "Each demonstrated shrug is judged once.")
        XCTAssertTrue(result.forms.allSatisfy { $0.flags.isEmpty }, "\(result.forms)")
        XCTAssertTrue(result.signals.allSatisfy(\.isEmpty), "\(result.signals.filter { !$0.isEmpty })")

        let expectedTop = 0.22 * Double(ExerciseDemoFigureView.upperArm / figureShoulderWidth)
        XCTAssertEqual(try XCTUnwrap(result.restLift), 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(result.topLift), expectedTop, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(result.topLift), 0.167, accuracy: 0.001)

        let thresholds = try XCTUnwrap(result.thresholds.last?[.left])
        XCTAssertEqual(thresholds.startLine.label, "Rest ↓")
        XCTAssertEqual(thresholds.topLine.label, "Top ↑")
        XCTAssertLessThan(thresholds.topLine.y, thresholds.startLine.y, "Top sits above Rest on screen.")
        XCTAssertNil(result.thresholds.last?[.right], "One segment spans both shoulders.")
    }

    func testReadingsAreScaleInvariantAndCountWithSegmentsAndDurationsPlusOrMinusFifteenPercent() {
        let base = run(motion)
        for (scale, offset) in [(CGFloat(0.5), CGPoint(x: 400, y: 900)), (CGFloat(2), CGPoint(x: 100, y: 300))] {
            let scaled = run(motion, scale: scale, offset: offset)
            XCTAssertEqual(scaled.reps, 3, "Scale \(scale)")
            XCTAssertEqual(scaled.lifts.count, base.lifts.count)
            for (scaledLift, baseLift) in zip(scaled.lifts, base.lifts) {
                XCTAssertEqual(scaledLift, baseLift, accuracy: 1e-9)
            }
            XCTAssertEqual(scaled.forms.map(\.flags), base.forms.map(\.flags))
        }

        for factor in [0.85, 1.15] {
            var keyframes = motion.keyframes
            for index in keyframes.indices where keyframes[index].moveDuration > 0 {
                keyframes[index].moveDuration *= factor
            }
            let changed = ArmMotion(keyframes: keyframes, forearmPlane: motion.forearmPlane,
                                    holdsDumbbells: motion.holdsDumbbells)
            let result = run(changed)
            XCTAssertEqual(result.reps, 3, "Move duration factor: \(factor)")
            XCTAssertTrue(result.forms.allSatisfy { $0.flags.isEmpty }, "Move duration factor: \(factor)")
        }

        for segmentScale in [CGFloat(0.85), 1.15] {
            XCTAssertEqual(run(motion, upperArmScale: segmentScale).reps, 3, "Upper arm \(segmentScale)")
            XCTAssertEqual(run(motion, forearmScale: segmentScale).reps, 3, "Forearm \(segmentScale)")
        }
    }

    func testHalfShrugDoesNotCountAndAsksToLiftHigher() {
        let result = run(shrugMotion(lift: 0.11))
        XCTAssertEqual(result.reps, 0)
        XCTAssertGreaterThanOrEqual(result.forms.count, 2)
        XCTAssertTrue(result.forms.allSatisfy { $0.flags.contains(.shrugHigher) }, "\(result.forms)")
    }

    func testUnevenShrugAsksForEvenShoulders() {
        let result = run(motion, rightLiftScale: 0.55)
        XCTAssertEqual(result.reps, 3, "The midpoint still reaches the Top.")
        XCTAssertGreaterThanOrEqual(result.forms.count, 2)
        XCTAssertTrue(result.forms.allSatisfy { $0.flags.contains(.shrugEven) }, "\(result.forms)")
        XCTAssertFalse(result.forms.contains { $0.flags.contains(.shrugHigher) })
    }

    func testShoulderThatCatchesUpByThePeakIsNotUneven() {
        // The right shoulder trails by 0.3 s, so the sides differ by about 0.09 on the way up but match at the peak.
        let result = run(motion, rightDelay: 0.3)
        XCTAssertEqual(result.reps, 3)
        XCTAssertGreaterThanOrEqual(result.forms.count, 2)
        XCTAssertFalse(result.forms.contains { $0.flags.contains(.shrugEven) }, "\(result.forms)")
    }

    func testBentElbowsAskForStraightArmsOnlyWhileLifting() {
        let bent = ArmAngles(upperArmElevation: -88, forearmElevation: -30)
        let result = run(motion, armAngles: bent)
        XCTAssertEqual(result.reps, 3, "Bent arms never affect counting.")
        XCTAssertTrue(result.signals.contains { $0.contains(.shrugArmsStraight) })
        XCTAssertFalse(result.signals.prefix(10).contains { $0.contains(.shrugArmsStraight) },
                       "The relaxed start is not judged.")
    }

    func testMovingOnlyTheArmsDoesNotCount() {
        let curl = ArmMotion(keyframes: [
            ArmKeyframe(angles: motion.startAngles, moveDuration: 0, holdDuration: 1.0, stepIndex: 0),
            ArmKeyframe(angles: ArmAngles(upperArmElevation: -80, forearmElevation: 70),
                        moveDuration: 0.8, holdDuration: 0.6, stepIndex: 1),
            ArmKeyframe(angles: motion.startAngles, moveDuration: 1.2, holdDuration: 0, stepIndex: 2)
        ], forearmPlane: .sagittal, holdsDumbbells: true)
        let result = run(curl)
        XCTAssertEqual(result.reps, 0)
        XCTAssertTrue(result.forms.isEmpty)
    }

    func testRisingOntoTheToesDoesNotCount() {
        // The whole body rises as far as the demo's shoulders do, so the nose rises with the shoulders.
        let relaxed = shrugMotion(lift: 0)
        let guide = motion
        let rise: (TimeInterval) -> CGFloat = { time in
            CGFloat(guide.sample(at: time).shape.shoulderLift) * ExerciseDemoFigureView.upperArm
        }
        let result = run(relaxed, bodyRise: rise)
        XCTAssertEqual(result.reps, 0)
        XCTAssertTrue(result.forms.isEmpty)
        XCTAssertTrue(result.lifts.allSatisfy { abs($0) < 1e-9 })
    }

    func testTorsoDriftNeedsHips() {
        let shift: (TimeInterval) -> CGFloat = { $0 >= 4.5 ? 16 : 0 }
        let drifting = run(motion, torsoShift: shift)
        XCTAssertTrue(drifting.signals.contains { $0.contains(.shrugTorso) })
        XCTAssertFalse(drifting.signals.prefix(45).contains { $0.contains(.shrugTorso) })
        XCTAssertEqual(drifting.reps, 3)

        let noHips = run(motion, torsoShift: shift, hips: false)
        XCTAssertFalse(noHips.signals.contains { $0.contains(.shrugTorso) })
        XCTAssertEqual(noHips.reps, 3)
    }

    func testGapAfterTheTopInvalidatesTheCycleAndReacquiresAfterTranslationAndScaleChange() throws {
        let result = run(motion, skipRange: 1.9...2.3, transformAfter: 2.4, scaleAfter: 0.6,
                         offsetAfter: CGPoint(x: 300, y: 600))
        XCTAssertEqual(result.reps, 2)
        XCTAssertGreaterThan(result.repTimes.first ?? 0, motion.duration * 1.5,
                             "The interrupted first cycle must not count.")

        // The first frame after the gap measures its rest line from that frame alone.
        let reacquired = try XCTUnwrap(result.reacquired)
        let line = try XCTUnwrap(reacquired.thresholds[.left]?.startLine)
        XCTAssertEqual(line.y, reacquired.expectedRestY, accuracy: 1e-6)
        XCTAssertEqual((line.from.x + line.to.x) / 2, reacquired.expectedCenterX, accuracy: 1e-6)
        XCTAssertEqual(line.to.x - line.from.x, reacquired.expectedLength, accuracy: 1e-6)
    }

    func testReferenceExpiryDiscardsTheHeldTopCycleAndACompleteShrugCountsAfterReacquiring() {
        let analyzer = DumbbellShrugAnalyzer(epoch: 1)
        var eventsWhileHeld = 0
        for index in 0...70 {
            let time = Double(index) / 10
            let lift = time < 0.5 ? 0 : 0.15
            eventsWhileHeld += analyzer.process(syntheticFrame(SyntheticSample(time: time, lift: lift)),
                                                counting: true).repEvents.count
        }
        XCTAssertEqual(eventsWhileHeld, 0, "Holding the raised shoulders through reference expiry is not a rep.")

        for index in 71...78 {
            let time = Double(index) / 10
            _ = analyzer.process(syntheticFrame(SyntheticSample(time: time, lift: 0)), counting: true)
        }

        var freshEvents: [RepEvent] = []
        for sample in cycleSamples(topLift: 0.15) {
            let reacquired = SyntheticSample(time: sample.time + 7.9, lift: sample.lift,
                                             bentElbows: sample.bentElbows,
                                             armAngleBelowHorizontal: sample.armAngleBelowHorizontal)
            freshEvents += analyzer.process(syntheticFrame(reacquired), counting: true).repEvents
        }
        XCTAssertEqual(freshEvents.count, 1, "A complete shrug after a fresh Rest must count.")
        XCTAssertEqual(freshEvents.map(\.sides), [Set(BodySide.allCases)])
    }

    func testContinuousScaleChangesBetweenRepsKeepRestNearZeroAndCountTheNextShrug() {
        for changedScale in [CGFloat(0.75), 1.33] {
            let scaleTime = motion.duration + 0.2
            let result = run(motion, loops: 2, transformAfter: scaleTime, scaleAfter: changedScale)

            XCTAssertEqual(result.reps, 2, "Scale \(changedScale) must not add or lose a rep.")
            XCTAssertEqual(result.repTimes.count, 2, "Scale \(changedScale) must produce only the two real shrugs.")
            XCTAssertEqual(result.repTimes.filter { $0 < scaleTime }.count, 1,
                           "The first real shrug must finish before changing to \(changedScale)×.")
            XCTAssertEqual(result.repTimes.filter { $0 >= scaleTime + 0.8 }.count, 1,
                           "The next real shrug must count after changing to \(changedScale)×.")
            let relaxedLifts = result.lifts.enumerated().compactMap { index, lift -> Double? in
                let time = Double(index) / 10
                return time >= scaleTime + 0.5 && time <= scaleTime + 0.7 ? lift : nil
            }
            XCTAssertFalse(relaxedLifts.isEmpty, "Expected relaxed samples after changing to \(changedScale)×.")
            XCTAssertTrue(relaxedLifts.allSatisfy { abs($0) <= 0.02 },
                          "The scaled Rest should read near zero: \(relaxedLifts)")
        }
    }

    func testEightRepsWithNearThresholdReturnsDoNotRatchetTheRestReference() {
        // After a true rest, every return stops 0.03 shoulder widths above it (inside Rest, alternating ±0.4 px),
        // and every top is 0.12 above it. Re-locking at those returns would leave the tops below the Top line.
        let width = figureShoulderWidth
        let upperArm = ExerciseDemoFigureView.upperArm
        let nearRest = Double(0.03 * width / upperArm)
        let top = Double(0.12 * width / upperArm)
        let nearMotion = shrugMotion(lift: top, restLift: nearRest)
        let extraLift: (TimeInterval) -> CGFloat = { time in
            if time < 1.0 { return -CGFloat(nearRest) * upperArm }
            return Int(time / nearMotion.duration).isMultiple(of: 2) ? 0.4 : -0.4
        }
        let result = run(nearMotion, loops: 8, extraLift: extraLift)
        XCTAssertEqual(result.reps, 8)

        let lockedLines = result.thresholds.compactMap { $0[.left] }.filter(\.isLocked).map(\.topLine.y)
        XCTAssertGreaterThan(lockedLines.count, 200)
        XCTAssertEqual((lockedLines.max() ?? 0) - (lockedLines.min() ?? 0), 0, accuracy: 0.001)
    }

    func testEstimatedArmJointsSuppressFormWhileCountingContinues() {
        let bent = ArmAngles(upperArmElevation: -88, forearmElevation: -30)
        let result = run(motion, rightLiftScale: 0.5, armAngles: bent, estimatedJoints: [.leftWrist])
        XCTAssertEqual(result.reps, 3)
        XCTAssertTrue(result.forms.isEmpty, "\(result.forms)")
        XCTAssertTrue(result.signals.allSatisfy(\.isEmpty))
    }

    func testTopBoundariesEmitRepEventsAndCreditBothSides() {
        let cases: [(label: String, top: Double, counts: Bool)] = [
            ("below", 0.099, false),
            ("at", 0.10, true),
            ("above", 0.101, true)
        ]
        for testCase in cases {
            let result = run(cycleSamples(topLift: testCase.top))
            XCTAssertEqual(result.reps, testCase.counts ? 1 : 0, testCase.label)
            XCTAssertEqual(result.repSides, testCase.counts ? [Set(BodySide.allCases)] : [], testCase.label)
        }
    }

    func testRestBoundariesEmitRepEventsAndCreditBothSides() {
        let cases: [(label: String, rest: Double, counts: Bool)] = [
            ("below", 0.039, true),
            ("at", 0.04, true),
            ("above", 0.041, false)
        ]
        for testCase in cases {
            let result = run(cycleSamples(topLift: 0.15, returnLift: testCase.rest))
            XCTAssertEqual(result.reps, testCase.counts ? 1 : 0, testCase.label)
            XCTAssertEqual(result.repSides, testCase.counts ? [Set(BodySide.allCases)] : [], testCase.label)
        }
    }

    func testSingleTopSampleCannotConfirmARep() {
        let lifts = [0.0, 0, 0, 0.15, 0.07, 0, 0, 0, 0]
        let result = run(lifts.enumerated().map { SyntheticSample(time: Double($0.offset) / 10, lift: $0.element) })
        XCTAssertEqual(result.reps, 0)
    }

    func testMinimumRepDurationRejectsJustUnderAndAcceptsExactlyPointEightSeconds() {
        let under = run(cycleSamples(topLift: 0.15, endTime: 0.9))
        XCTAssertEqual(under.reps, 0)

        let exact = run(cycleSamples(topLift: 0.15, endTime: 1.0))
        XCTAssertEqual(exact.reps, 1)
        XCTAssertEqual(exact.repTimes, [1.0])
        XCTAssertEqual(exact.repSides, [Set(BodySide.allCases)])
    }

    func testHoldingTheStartNeedsStraightHangingArms() {
        let hanging = run((0..<4).map { SyntheticSample(time: Double($0) / 10, lift: 0) })
        XCTAssertEqual(hanging.startHeld, [false, true, true, true])

        let bent = run((0..<4).map { SyntheticSample(time: Double($0) / 10, lift: 0, bentElbows: true) })
        XCTAssertEqual(bent.startHeld, [false, false, false, false])

        let armsOut = run((0..<4).map {
            SyntheticSample(time: Double($0) / 10, lift: 0, armAngleBelowHorizontal: 5)
        })
        XCTAssertEqual(armsOut.startHeld, [false, false, false, false],
                       "Straight arms only a few degrees below horizontal are not hanging.")

        let armsForward = run((0..<4).map {
            SyntheticSample(time: Double($0) / 10, lift: 0, armAngleBelowHorizontal: 30)
        })
        XCTAssertEqual(armsForward.startHeld, [false, false, false, false],
                       "Straight arms with wrists only slightly below the shoulders are not hanging.")
    }

    func testDefinitionMatchesTheIssue() throws {
        XCTAssertEqual(exercise.id.rawValue, "dumbbell_shrug")
        XCTAssertEqual(exercise.displayName, "Dumbbell Shrug")
        XCTAssertEqual(exercise.presentation.shortName, "Shrug")
        XCTAssertEqual(exercise.spokenName, "dumbbell shrug")
        XCTAssertEqual(exercise.sets, 2)
        XCTAssertEqual(exercise.targetReps, 12...12)
        XCTAssertEqual(exercise.autoCompleteReps, 12)
        XCTAssertEqual(exercise.restSeconds, 60)
        XCTAssertEqual(exercise.equipment, .dumbbells)
        XCTAssertEqual(exercise.presentation.filterGroups, [.upper, .dumbbells])
        XCTAssertEqual(exercise.cameraView, .front)
        XCTAssertNil(exercise.headroomArmLengths)
        XCTAssertTrue(exercise.startsByHolding)
        XCTAssertEqual(exercise.requiredJoints, [.nose, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
                                                  .leftWrist, .rightWrist])
        XCTAssertEqual(exercise.voiceAliases,
                       ["dumbbell shrug", "dumbbell shrugs", "shrug", "shrugs", "shoulder shrugs"])
        let parser = VoiceCommandParser(exercises: ExerciseCatalog.all)
        for alias in exercise.voiceAliases {
            XCTAssertEqual(parser.parse(alias)?.command, .selectExercise(.dumbbellShrug), alias)
        }

        let photograph = try XCTUnwrap(ExercisePhotography.photograph(for: .dumbbellShrug))
        XCTAssertEqual(photograph.exerciseName, "Dumbbell Shrug")
        XCTAssertEqual(photograph.assetName, "ExerciseThumbnails/dumbbell_shrug")
        XCTAssertEqual(photograph.photographer, "Tima Miroshnichenko")
        XCTAssertEqual(photograph.source, "Pexels")
        XCTAssertEqual(photograph.sourceURL.absoluteString,
                       "https://www.pexels.com/photo/man-in-black-tank-top-holding-dumbbells-5327450/")
        XCTAssertEqual(photograph.license, "Pexels License")
    }

    // MARK: - Helpers

    private struct Run {
        var reps = 0
        var repTimes: [TimeInterval] = []
        var repSides: [Set<BodySide>] = []
        /// The shoulder-midpoint lift on each analyzed frame.
        var lifts: [Double] = []
        var thresholds: [[BodySide: ArmThresholds]] = []
        var forms: [RepForm] = []
        var signals: [Set<CoachingCueID>] = []
        var startHeld: [Bool] = []
        var restLift: Double?
        var topLift: Double?
        var reacquired: (thresholds: [BodySide: ArmThresholds], expectedRestY: CGFloat,
                         expectedCenterX: CGFloat, expectedLength: CGFloat)?

        mutating func record(_ analysis: ExerciseAnalysis) {
            reps += analysis.repEvents.count
            repTimes += analysis.repEvents.map(\.timestamp)
            repSides += analysis.repEvents.map(\.sides)
            if let left = analysis.readings[.left]?.signal, let right = analysis.readings[.right]?.signal {
                lifts.append((left + right) / 2)
            }
            thresholds.append(analysis.thresholds)
            forms += analysis.repForms
            signals.append(analysis.formSignals)
            startHeld.append(analysis.startPositionHeld)
        }
    }

    private struct SyntheticSample {
        let time: TimeInterval
        let lift: Double
        var bentElbows = false
        var armAngleBelowHorizontal: Double?
    }

    private func shrugMotion(lift: Double, restLift: Double = 0) -> ArmMotion {
        let arms = motion.startAngles
        return ArmMotion(keyframes: [
            ArmKeyframe(angles: arms, moveDuration: 0, holdDuration: 1.0, stepIndex: 0,
                        shape: FigureShape(shoulderLift: restLift)),
            ArmKeyframe(angles: arms, moveDuration: 0.8, holdDuration: 0.6, stepIndex: 1,
                        shape: FigureShape(shoulderLift: lift)),
            ArmKeyframe(angles: arms, moveDuration: 1.2, holdDuration: 0, stepIndex: 2,
                        shape: FigureShape(shoulderLift: restLift))
        ], forearmPlane: .frontal, holdsDumbbells: true)
    }

    private func cycleSamples(topLift: Double, returnLift: Double = 0,
                              endTime: TimeInterval = 1.1) -> [SyntheticSample] {
        var samples = [SyntheticSample(time: 0, lift: 0), SyntheticSample(time: 0.1, lift: 0),
                       SyntheticSample(time: 0.2, lift: 0)]
        let finalTopIndex = Int((endTime - 0.3) * 10)
        if finalTopIndex >= 3 {
            for index in 3...finalTopIndex {
                samples.append(SyntheticSample(time: Double(index) / 10, lift: topLift))
            }
        }
        samples.append(SyntheticSample(time: endTime - 0.1, lift: returnLift))
        samples.append(SyntheticSample(time: endTime, lift: returnLift))
        return samples
    }

    private func run(_ samples: [SyntheticSample]) -> Run {
        let analyzer = DumbbellShrugAnalyzer(epoch: 1)
        var result = Run()
        for sample in samples {
            result.record(analyzer.process(syntheticFrame(sample), counting: true))
        }
        return result
    }

    /// Shoulders 200 px apart with the nose 100 px above them at rest, so a lift of 0.1 raises them 20 px.
    private func syntheticFrame(_ sample: SyntheticSample) -> PoseFrame {
        let nose = CGPoint(x: 540, y: 500)
        let shoulderY = nose.y + CGFloat(0.5 - sample.lift) * 200
        var joints: [LandmarkType: CGPoint] = [.nose: nose]
        for side in BodySide.allCases {
            let direction: CGFloat = side == .left ? 1 : -1
            let shoulder = CGPoint(x: 540 + direction * 100, y: shoulderY)
            joints[side.shoulder] = shoulder
            if sample.bentElbows {
                let elbow = CGPoint(x: shoulder.x, y: shoulder.y + 120)
                joints[side.elbow] = elbow
                joints[side.wrist] = CGPoint(x: elbow.x - direction * 100, y: elbow.y)
            } else if let angle = sample.armAngleBelowHorizontal {
                let radians = angle * .pi / 180
                let dx = CGFloat(cos(radians)) * direction
                let dy = CGFloat(sin(radians))
                let elbow = CGPoint(x: shoulder.x + dx * 120, y: shoulder.y + dy * 120)
                joints[side.elbow] = elbow
                joints[side.wrist] = CGPoint(x: shoulder.x + dx * 220, y: shoulder.y + dy * 220)
            } else {
                let elbow = CGPoint(x: shoulder.x, y: shoulder.y + 120)
                joints[side.elbow] = elbow
                joints[side.wrist] = CGPoint(x: shoulder.x, y: shoulder.y + 220)
            }
            joints[side.hip] = CGPoint(x: 540 + direction * 70, y: 900)
        }
        return frame(joints, at: sample.time)
    }

    private func frame(_ joints: [LandmarkType: CGPoint], at time: TimeInterval,
                       estimatedJoints: Set<LandmarkType> = []) -> PoseFrame {
        let landmarks = Dictionary(uniqueKeysWithValues: joints.map { type, point in
            (type, Landmark(type: type, normalizedLocation: .zero, imageLocation: point, confidence: 0.9))
        })
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920),
                         timestamp: time, estimatedJoints: estimatedJoints)
    }

    /// Samples a front-view motion at 10 Hz. The pose comes from the guide figure, so its shoulders rise by the
    /// keyframes' `shoulderLift`; the arms are then re-hung from the shoulders with the requested proportions.
    private func run(
        _ motion: ArmMotion,
        loops: Int = 3,
        scale: CGFloat = 1,
        offset: CGPoint = .zero,
        upperArmScale: CGFloat = 1,
        forearmScale: CGFloat = 1,
        rightLiftScale: CGFloat = 1,
        rightDelay: TimeInterval = 0,
        armAngles: ArmAngles? = nil,
        extraLift: (TimeInterval) -> CGFloat = { _ in 0 },
        bodyRise: (TimeInterval) -> CGFloat = { _ in 0 },
        torsoShift: (TimeInterval) -> CGFloat = { _ in 0 },
        hips: Bool = true,
        estimatedJoints: Set<LandmarkType> = [],
        skipRange: ClosedRange<TimeInterval>? = nil,
        transformAfter: TimeInterval? = nil,
        scaleAfter: CGFloat = 1,
        offsetAfter: CGPoint = .zero
    ) -> Run {
        let analyzer = DumbbellShrugAnalyzer(epoch: 1)
        var result = Run()
        let upperArm = ExerciseDemoFigureView.upperArm
        let frameCount = Int(ceil(motion.duration * 10)) * loops + 10
        let topTime = (motion.keyframes.first?.holdDuration ?? 0)
            + (motion.keyframes.dropFirst().first?.moveDuration ?? 0)
        for index in 0..<frameCount {
            let time = Double(index) / 10
            if let skipRange, skipRange.contains(time) { continue }
            let sample = motion.sample(at: time)
            var joints = ExerciseDemoFigureView.pose(for: sample, cameraView: .front).jointLocations

            let rightSample = motion.sample(at: max(0, time - rightDelay))
            if let relaxed = ExerciseDemoFigureView.figureJoints[.rightShoulder] {
                let rise = CGFloat(rightSample.shape.shoulderLift) * upperArm * rightLiftScale
                joints[.rightShoulder] = CGPoint(x: relaxed.x, y: relaxed.y - rise)
            }
            for side in BodySide.allCases {
                joints[side.shoulder]?.y -= extraLift(time)
            }
            for side in BodySide.allCases {
                let other: BodySide = side == .left ? .right : .left
                guard let shoulder = joints[side.shoulder], let otherShoulder = joints[other.shoulder] else { continue }
                let arm = ArmMotion.place(shoulder: shoulder, otherShoulder: otherShoulder,
                                          upperArm: upperArm * upperArmScale,
                                          forearm: ExerciseDemoFigureView.forearm * forearmScale,
                                          angles: armAngles ?? sample.angles, forearmPlane: motion.forearmPlane)
                joints[side.elbow] = arm.elbow
                joints[side.wrist] = arm.wrist
            }
            let shift = torsoShift(time)
            for joint in [LandmarkType.nose, .neck] + BodySide.allCases.flatMap(\.armJoints) {
                joints[joint]?.x += shift
            }
            let rise = bodyRise(time)
            for joint in Array(joints.keys) {
                joints[joint]?.y -= rise
            }
            if !hips {
                joints[.leftHip] = nil
                joints[.rightHip] = nil
            }

            let acquired = transformAfter.map { time >= $0 } ?? false
            let currentScale = acquired ? scaleAfter : scale
            let currentOffset = acquired ? offsetAfter : offset
            let pixels = joints.mapValues { point in
                CGPoint(x: point.x * currentScale + currentOffset.x, y: point.y * currentScale + currentOffset.y)
            }
            let analysis = analyzer.process(frame(pixels, at: time, estimatedJoints: estimatedJoints),
                                            counting: true)
            result.record(analysis)

            if let readingLeft = analysis.readings[.left]?.signal, let readingRight = analysis.readings[.right]?.signal {
                if time == 0 { result.restLift = (readingLeft + readingRight) / 2 }
                if abs(time - topTime) < 0.001 { result.topLift = (readingLeft + readingRight) / 2 }
            }
            if let transformAfter, abs(time - transformAfter) < 0.001,
               let nose = pixels[.nose], let left = pixels[.leftShoulder], let right = pixels[.rightShoulder] {
                let width = ArmGeometry.distance(left, right)
                let middle = ArmGeometry.midpoint(left, right)
                result.reacquired = (analysis.thresholds,
                                     nose.y + (middle.y - nose.y) - 0.04 * width,
                                     middle.x,
                                     1.2 * width)
            }
        }
        return result
    }
}
