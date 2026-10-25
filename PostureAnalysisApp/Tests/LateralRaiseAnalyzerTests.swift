import CoreGraphics
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class LateralRaiseAnalyzerTests: XCTestCase {
    private let exercise = LateralRaiseExercise.definition()
    private var motion: ArmMotion { exercise.guide.motion }

    func testGuideDemonstrationCountsOneRepPerLoopAndMeasuresExpectedPositions() throws {
        let result = run(motion)
        XCTAssertEqual(result.reps, 3)
        XCTAssertEqual(result.repSides, Array(repeating: Set(BodySide.allCases), count: 3))
        XCTAssertTrue(result.forms.allSatisfy { $0.flags.isEmpty }, "\(result.forms)")
        XCTAssertTrue(result.signals.allSatisfy(\.isEmpty))

        for side in BodySide.allCases {
            let start = try XCTUnwrap(result.startMeasurements[side])
            let top = try XCTUnwrap(result.topMeasurements[side])
            XCTAssertEqual(start.height, -0.996, accuracy: 0.02)
            XCTAssertEqual(start.outward, 0.087, accuracy: 0.02)
            XCTAssertEqual(top.height, -0.065, accuracy: 0.02)
            XCTAssertEqual(top.outward, 0.995, accuracy: 0.02)
        }

        let thresholds = try XCTUnwrap(result.thresholds.first)
        XCTAssertEqual(thresholds[.left]?.startLine.label, "Start ↓")
        XCTAssertEqual(thresholds[.left]?.topLine.label, "Top ↑")
        XCTAssertEqual(thresholds[.right]?.startLine.label, "Start ↓")
        XCTAssertEqual(thresholds[.right]?.topLine.label, "Top ↑")
    }

    func testReadingsAreScaleInvariantAndCountWithBothSegmentsPlusOrMinusFifteenPercent() {
        let base = run(motion)
        for (scale, offset) in [(CGFloat(0.5), CGPoint(x: 400, y: 900)), (CGFloat(2), CGPoint(x: 100, y: 300))] {
            let scaled = run(motion, scale: scale, offset: offset)
            XCTAssertEqual(scaled.reps, 3)
            XCTAssertEqual(scaled.readings.count, base.readings.count)
            for (scaledFrame, baseFrame) in zip(scaled.readings, base.readings) {
                for side in BodySide.allCases {
                    XCTAssertEqual(scaledFrame[side] ?? 0, baseFrame[side] ?? 0, accuracy: 1e-9)
                }
            }
            XCTAssertEqual(scaled.forms.map(\.flags), base.forms.map(\.flags))
        }

        for factor in [0.85, 1.15] {
            var keyframes = motion.keyframes
            keyframes[1].moveDuration *= factor
            keyframes[2].moveDuration *= factor
            XCTAssertEqual(run(ArmMotion(keyframes: keyframes), loops: 3).reps, 3, "Segment duration factor: \(factor)")
        }

        XCTAssertEqual(run(motion, upperArmScale: 0.85).reps, 3)
        XCTAssertEqual(run(motion, upperArmScale: 1.15).reps, 3)
        XCTAssertEqual(run(motion, forearmScale: 0.85).reps, 3)
        XCTAssertEqual(run(motion, forearmScale: 1.15).reps, 3)
    }

    func testFrontRaiseDoesNotCountBecauseTheWristsDoNotMoveOutward() {
        let frontRaise = movement(
            start: motion.startAngles,
            top: ArmAngles(upperArmElevation: 80, forearmElevation: 80),
            forearmPlane: .sagittal
        )
        let result = run(frontRaise)
        XCTAssertEqual(result.reps, 0)
        XCTAssertTrue(result.forms.contains { $0.flags.contains(.lateralHigher) })
    }

    func testHalfRaiseAsksForMoreHeight() {
        let halfRaise = movement(
            start: motion.startAngles,
            top: ArmAngles(upperArmElevation: 0, forearmElevation: -45)
        )
        let result = run(halfRaise)
        XCTAssertEqual(result.reps, 0)
        XCTAssertTrue(result.forms.count >= 2)
        XCTAssertTrue(result.forms.allSatisfy { $0.flags.contains(.lateralHigher) }, "\(result.forms)")
    }

    func testLateArmAsksForEvenRaises() {
        let result = run(motion, rightDelay: 0.45)
        XCTAssertGreaterThanOrEqual(result.forms.count, 2)
        XCTAssertTrue(result.forms.allSatisfy { $0.flags.contains(.lateralEven) }, "\(result.forms)")
    }

    func testLowArmAsksForEvenRaises() {
        let start = motion.startAngles
        let result = run(motion, rightAngleTransform: { _, angles in
            ArmAngles(
                upperArmElevation: start.upperArmElevation + (angles.upperArmElevation - start.upperArmElevation) * 0.75,
                forearmElevation: start.forearmElevation + (angles.forearmElevation - start.forearmElevation) * 0.75
            )
        })
        XCTAssertTrue(result.forms.contains { $0.flags.contains(.lateralEven) }, "\(result.forms)")
    }

    func testShrugRaisesShouldersDownSignalOnlyWhenNoseIsVisible() {
        let shrug = run(motion, shoulderLift: 28)
        XCTAssertTrue(shrug.signals.contains { $0.contains(.lateralShouldersDown) })
        XCTAssertEqual(shrug.reps, 3, "Shrugging never affects counting.")

        let noNose = run(motion, shoulderLift: 28, includeNose: false)
        XCTAssertFalse(noNose.signals.contains { $0.contains(.lateralShouldersDown) })

        let estimatedNose = run(motion, shoulderLift: 28, estimatedJoints: [.nose])
        XCTAssertFalse(estimatedNose.signals.contains { $0.contains(.lateralShouldersDown) })
    }

    func testBentArmsAskForLongArms() {
        let bent = movement(
            start: motion.startAngles,
            top: ArmAngles(upperArmElevation: 10, forearmElevation: -35)
        )
        let result = run(bent)
        XCTAssertEqual(result.reps, 3)
        XCTAssertTrue(result.forms.allSatisfy { $0.flags.contains(.lateralArmsLong) }, "\(result.forms)")
    }

    func testTopHeightAndOutwardBoundariesEmitRepEventsAndCreditBothSides() {
        let cases: [(label: String, height: Double, outward: Double, counts: Bool)] = [
            ("height below", -0.201, 0.9, false),
            ("height at", -0.2, 0.9, true),
            ("height above", -0.199, 0.9, true),
            ("outward below", -0.05, 0.749, false),
            ("outward at", -0.05, 0.75, true),
            ("outward above", -0.05, 0.751, true)
        ]

        for testCase in cases {
            let result = run(cycleSamples(topHeight: testCase.height, topOutward: testCase.outward))
            XCTAssertEqual(result.reps, testCase.counts ? 1 : 0, testCase.label)
            XCTAssertEqual(result.repSides, testCase.counts ? [Set(BodySide.allCases)] : [], testCase.label)
        }
    }

    func testStartHeightBoundariesEmitRepEventsAndCreditBothSides() {
        let cases: [(label: String, height: Double, counts: Bool)] = [
            ("height below", -0.751, true),
            ("height at", -0.75, true),
            ("height above", -0.749, false)
        ]

        for testCase in cases {
            let result = run(cycleSamples(topHeight: -0.05, topOutward: 0.95,
                                          returnHeight: testCase.height))
            XCTAssertEqual(result.reps, testCase.counts ? 1 : 0, testCase.label)
            XCTAssertEqual(result.repSides, testCase.counts ? [Set(BodySide.allCases)] : [], testCase.label)
        }
    }

    func testSingleTopOrStartSampleCannotConfirmARepCheckpoint() {
        let singleTop = run([
            sample(0, height: -0.9, outward: 0.05),
            sample(0.1, height: -0.9, outward: 0.05),
            sample(0.2, height: -0.9, outward: 0.05),
            sample(0.3, height: -0.05, outward: 0.95),
            sample(0.4, height: -0.4, outward: 0.5),
            sample(0.5, height: -0.9, outward: 0.05),
            sample(0.6, height: -0.9, outward: 0.05)
        ])
        XCTAssertEqual(singleTop.reps, 0)
        XCTAssertTrue(singleTop.repSides.isEmpty)

        let singleStart = run([
            sample(0, height: -0.9, outward: 0.05),
            sample(0.1, height: -0.9, outward: 0.05),
            sample(0.2, height: -0.9, outward: 0.05),
            sample(0.3, height: -0.05, outward: 0.95),
            sample(0.4, height: -0.05, outward: 0.95),
            sample(0.5, height: -0.05, outward: 0.95),
            sample(0.6, height: -0.9, outward: 0.05),
            sample(0.7, height: -0.4, outward: 0.5),
            sample(0.8, height: -0.05, outward: 0.95),
            sample(0.9, height: -0.05, outward: 0.95),
            sample(1.0, height: -0.9, outward: 0.05),
            sample(1.1, height: -0.9, outward: 0.05)
        ])
        XCTAssertEqual(singleStart.reps, 1)
        XCTAssertEqual(singleStart.repTimes, [1.1])
        XCTAssertEqual(singleStart.repSides, [Set(BodySide.allCases)])
    }

    func testMinimumRepDurationRejectsJustUnderAndAcceptsExactlyPointEightSeconds() {
        let under = run(cycleSamples(topHeight: -0.05, topOutward: 0.95, endTime: 0.9))
        XCTAssertEqual(under.reps, 0)
        XCTAssertTrue(under.repSides.isEmpty)

        let exact = run(cycleSamples(topHeight: -0.05, topOutward: 0.95, endTime: 1.0))
        XCTAssertEqual(exact.reps, 1)
        XCTAssertEqual(exact.repTimes, [1.0])
        XCTAssertEqual(exact.repSides, [Set(BodySide.allCases)])
    }

    func testConsecutiveRepsFinishSeparateFormAttemptsOnTheConfirmedReturn() {
        var samples = [sample(0, height: -0.9, outward: 0.05),
                       sample(0.1, height: -0.9, outward: 0.05),
                       sample(0.2, height: -0.9, outward: 0.05),
                       sample(0.3, height: -0.45, outward: 0.5)]
        for index in 4...9 {
            samples.append(sample(Double(index) / 10, height: -0.065, outward: 0.995))
        }
        samples += [sample(1.0, height: -0.9, outward: 0.05),
                    sample(1.1, height: -0.9, outward: 0.05),
                    sample(1.2, height: -0.45, outward: 0.5),
                    sample(1.3, height: -0.065, outward: 0.9),
                    sample(1.4, height: -0.065, outward: 0.9),
                    sample(1.5, height: -0.065, outward: 0.9),
                    sample(1.6, height: -0.065, outward: 0.9),
                    sample(1.7, height: -0.065, outward: 0.9),
                    sample(1.8, height: -0.065, outward: 0.9),
                    sample(1.9, height: -0.065, outward: 0.9),
                    sample(2.0, height: -0.9, outward: 0.05),
                    sample(2.1, height: -0.9, outward: 0.05)]

        let result = run(samples)
        XCTAssertEqual(result.reps, 2)
        XCTAssertEqual(result.repSides, Array(repeating: Set(BodySide.allCases), count: 2))
        XCTAssertEqual(result.forms.count, 2, "Each confirmed return must finish one form attempt.")
        guard result.forms.count == 2 else { return }
        XCTAssertFalse(result.forms[0].flags.contains(.lateralArmsLong))
        XCTAssertTrue(result.forms[1].flags.contains(.lateralArmsLong), "The second rep uses bent arms.")
    }

    func testTorsoDriftNeedsHips() {
        let shift: (TimeInterval) -> CGFloat = { $0 >= 4.5 ? 22 : 0 }
        let leaning = run(motion, torsoShift: shift)
        XCTAssertTrue(leaning.signals.contains { $0.contains(.lateralTorsoCentered) })
        XCTAssertEqual(leaning.reps, 3)

        let noHips = run(motion, torsoShift: shift, hips: false)
        XCTAssertFalse(noHips.signals.contains { $0.contains(.lateralTorsoCentered) })
    }

    func testGapInvalidatesCycleAndReacquiresAfterTranslationAndScaleChange() {
        let result = run(
            motion,
            loops: 3,
            skipRange: 2.1...2.4,
            transformAfter: 2.5,
            scaleAfter: 1.5,
            offsetAfter: CGPoint(x: 240, y: 420)
        )
        XCTAssertEqual(result.reps, 2)
        XCTAssertGreaterThan(result.repTimes.first ?? 0, motion.duration * 1.5,
                             "The interrupted first cycle must not count.")
    }

    func testEightNearThresholdReturnsDoNotRatchetTheLockedReference() {
        let nearStart = ArmAngles(upperArmElevation: -50, forearmElevation: -50)
        let nearStartMotion = movement(start: nearStart, top: motion.topAngles)
        let offset: (TimeInterval, ArmAngles) -> CGFloat = { time, angles in
            guard angles.upperArmElevation < -45 else { return 0 }
            let cycle = Int(time / nearStartMotion.duration)
            return cycle.isMultiple(of: 2) ? 1 : -1
        }
        let result = run(nearStartMotion, loops: 8, startVerticalShift: offset)
        XCTAssertEqual(result.reps, 8)

        let lockedLines = result.thresholds.compactMap { $0[.left] }.filter(\.isLocked).map(\.topLine.y)
        XCTAssertGreaterThan(lockedLines.count, 20)
        XCTAssertEqual((lockedLines.max() ?? 0) - (lockedLines.min() ?? 0), 0, accuracy: 0.001)
    }

    func testEstimatedArmJointsSuppressFormWhileCountingContinues() {
        let result = run(motion, shoulderLift: 28, estimatedJoints: [.leftWrist])
        XCTAssertEqual(result.reps, 3)
        XCTAssertTrue(result.forms.isEmpty)
        XCTAssertTrue(result.signals.allSatisfy(\.isEmpty))
    }

    private struct Run {
        var reps = 0
        var repTimes: [TimeInterval] = []
        var repSides: [Set<BodySide>] = []
        var readings: [[BodySide: Double]] = []
        var thresholds: [[BodySide: ArmThresholds]] = []
        var forms: [RepForm] = []
        var signals: [Set<CoachingCueID>] = []
        var startMeasurements: [BodySide: (height: Double, outward: Double)] = [:]
        var topMeasurements: [BodySide: (height: Double, outward: Double)] = [:]
    }

    private struct FrameSample {
        let time: TimeInterval
        let height: Double
        let outward: Double
        var upperArmLength: CGFloat = 100
        var forearmLength: CGFloat = 100
    }

    private func sample(_ time: TimeInterval, height: Double, outward: Double) -> FrameSample {
        FrameSample(time: time, height: height, outward: outward)
    }

    private func cycleSamples(topHeight: Double, topOutward: Double,
                              returnHeight: Double = -0.9, endTime: TimeInterval = 1.1) -> [FrameSample] {
        var samples = [sample(0, height: -0.9, outward: 0.05),
                       sample(0.1, height: -0.9, outward: 0.05),
                       sample(0.2, height: -0.9, outward: 0.05)]
        let finalTopIndex = Int((endTime - 0.3) * 10)
        if finalTopIndex >= 3 {
            for index in 3...finalTopIndex {
                samples.append(sample(Double(index) / 10, height: topHeight, outward: topOutward))
            }
        }
        samples.append(sample(endTime - 0.1, height: returnHeight, outward: 0.05))
        samples.append(sample(endTime, height: returnHeight, outward: 0.05))
        return samples
    }

    private func run(_ samples: [FrameSample]) -> Run {
        let analyzer = LateralRaiseAnalyzer(epoch: 1)
        var result = Run()
        for sample in samples {
            let analysis = analyzer.process(frame(for: sample), counting: true)
            result.reps += analysis.repEvents.count
            result.repSides += analysis.repEvents.map(\.sides)
            result.repTimes += analysis.repEvents.map(\.timestamp)
            result.forms += analysis.repForms
            result.signals.append(analysis.formSignals)
        }
        return result
    }

    private func frame(for sample: FrameSample) -> PoseFrame {
        let imageWidth: CGFloat = 1080
        let imageHeight: CGFloat = 1920
        let armLength = sample.upperArmLength + sample.forearmLength
        var joints: [LandmarkType: CGPoint] = [:]
        for side in BodySide.allCases {
            let shoulder = CGPoint(x: side == .left ? 680 : 400, y: 600)
            let direction: CGFloat = side == .left ? 1 : -1
            let wrist = CGPoint(x: shoulder.x + direction * CGFloat(sample.outward) * armLength,
                                y: shoulder.y - CGFloat(sample.height) * armLength)
            let dx = wrist.x - shoulder.x
            let dy = wrist.y - shoulder.y
            let distance = hypot(dx, dy)
            let along = (sample.upperArmLength * sample.upperArmLength
                         + distance * distance - sample.forearmLength * sample.forearmLength) / (2 * distance)
            let offset = sqrt(max(0, sample.upperArmLength * sample.upperArmLength - along * along))
            let elbow = CGPoint(x: shoulder.x + dx / distance * along - dy / distance * offset,
                                y: shoulder.y + dy / distance * along + dx / distance * offset)
            joints[side.shoulder] = shoulder
            joints[side.elbow] = elbow
            joints[side.wrist] = wrist
            joints[side.hip] = CGPoint(x: shoulder.x, y: 950)
        }
        joints[.nose] = CGPoint(x: 540, y: 500)
        let landmarks = Dictionary(uniqueKeysWithValues: joints.map { type, point in
            (type, Landmark(type: type,
                            normalizedLocation: CoordinateConverter.imagePixelToNormalized(
                                pixel: point, imageWidth: imageWidth, imageHeight: imageHeight),
                            imageLocation: point,
                            confidence: 0.9))
        })
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: imageWidth, imageHeight: imageHeight),
                         timestamp: sample.time)
    }

    private func run(
        _ motion: ArmMotion,
        loops: Int = 3,
        scale: CGFloat = 1,
        offset: CGPoint = .zero,
        upperArmScale: CGFloat = 1,
        forearmScale: CGFloat = 1,
        rightDelay: TimeInterval = 0,
        rightAngleTransform: ((TimeInterval, ArmAngles) -> ArmAngles)? = nil,
        shoulderLift: CGFloat = 0,
        torsoShift: (TimeInterval) -> CGFloat = { _ in 0 },
        startVerticalShift: (TimeInterval, ArmAngles) -> CGFloat = { _, _ in 0 },
        hips: Bool = true,
        includeNose: Bool = true,
        estimatedJoints: Set<LandmarkType> = [],
        skipRange: ClosedRange<TimeInterval>? = nil,
        transformAfter: TimeInterval? = nil,
        scaleAfter: CGFloat = 1,
        offsetAfter: CGPoint = .zero
    ) -> Run {
        let analyzer = LateralRaiseAnalyzer(epoch: 1)
        var result = Run()
        let frameCount = Int(ceil(motion.duration * 10)) * loops + 10
        let topTime = (motion.keyframes.first?.holdDuration ?? 0)
            + (motion.keyframes.dropFirst().first?.moveDuration ?? 0)
        for index in 0..<frameCount {
            let time = Double(index) / 10
            if let skipRange, skipRange.contains(time) { continue }
            let sample = motion.sample(at: time)
            var joints = ExerciseDemoFigureView.pose(for: sample, cameraView: .front).jointLocations
            let rightTime = max(0, time - rightDelay)
            let rightSample = motion.sample(at: rightTime)
            let rightAngles = rightAngleTransform?(time, rightSample.angles) ?? rightSample.angles
            for side in BodySide.allCases {
                guard let shoulder = joints[side.shoulder],
                      let otherShoulder = joints[side == .left ? .rightShoulder : .leftShoulder] else { continue }
                let angles = side == .right ? rightAngles : sample.angles
                let arm = ArmMotion.place(
                    shoulder: shoulder,
                    otherShoulder: otherShoulder,
                    upperArm: ExerciseDemoFigureView.upperArm * upperArmScale,
                    forearm: ExerciseDemoFigureView.forearm * forearmScale,
                    angles: angles,
                    forearmPlane: motion.forearmPlane
                )
                joints[side.elbow] = arm.elbow
                joints[side.wrist] = arm.wrist

                let raisedRange = max(motion.topAngles.upperArmElevation - motion.startAngles.upperArmElevation, 1)
                let progress = max(0, min(1, (angles.upperArmElevation - motion.startAngles.upperArmElevation) / raisedRange))
                let verticalRaise = shoulderLift * CGFloat(progress)
                let nearStartShift = startVerticalShift(time, angles)
                for joint in side.armJoints {
                    joints[joint]?.y += nearStartShift - verticalRaise
                    joints[joint]?.x += torsoShift(time)
                }
            }

            if !hips {
                joints[.leftHip] = nil
                joints[.rightHip] = nil
            }
            if !includeNose { joints[.nose] = nil }

            let acquired = transformAfter.map { time >= $0 } ?? false
            let currentScale = acquired ? scaleAfter : scale
            let currentOffset = acquired ? offsetAfter : offset
            let landmarks = Dictionary(uniqueKeysWithValues: joints.map { type, point in
                (type, Landmark(type: type, normalizedLocation: .zero,
                                imageLocation: CGPoint(x: point.x * currentScale + currentOffset.x,
                                                       y: point.y * currentScale + currentOffset.y),
                                confidence: 0.9))
            })
            let frame = PoseFrame(
                pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920),
                timestamp: time,
                estimatedJoints: estimatedJoints
            )
            let analysis = analyzer.process(frame, counting: true)
            result.repSides += analysis.repEvents.map(\.sides)
            result.reps += analysis.repEvents.count
            result.repTimes += analysis.repEvents.map(\.timestamp)
            result.readings.append(analysis.readings.mapValues(\.signal))
            result.thresholds.append(analysis.thresholds)
            result.forms += analysis.repForms
            result.signals.append(analysis.formSignals)

            if time == 0 || abs(time - topTime) < 0.001 {
                for side in BodySide.allCases {
                    guard let shoulder = landmarks[side.shoulder]?.imageLocation,
                          let elbow = landmarks[side.elbow]?.imageLocation,
                          let wrist = landmarks[side.wrist]?.imageLocation else { continue }
                    let length = ArmGeometry.distance(shoulder, elbow) + ArmGeometry.distance(elbow, wrist)
                    let measured = (height: Double((shoulder.y - wrist.y) / length),
                                    outward: Double(abs(wrist.x - shoulder.x) / length))
                    if time == 0 { result.startMeasurements[side] = measured }
                    else { result.topMeasurements[side] = measured }
                }
            }
        }
        return result
    }

    private func movement(start: ArmAngles, top: ArmAngles, forearmPlane: MotionPlane = .frontal) -> ArmMotion {
        ArmMotion(keyframes: [
            ArmKeyframe(angles: start, moveDuration: 0, holdDuration: 1.0, stepIndex: 0),
            ArmKeyframe(angles: top, moveDuration: 1.0, holdDuration: 0.4, stepIndex: 1),
            ArmKeyframe(angles: start, moveDuration: 1.5, holdDuration: 0, stepIndex: 2)
        ], forearmPlane: forearmPlane, holdsDumbbells: true)
    }
}
