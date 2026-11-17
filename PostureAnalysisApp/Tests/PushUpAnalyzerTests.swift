import XCTest
@testable import PostureAnalysisApp

final class PushUpAnalyzerTests: XCTestCase {
    private let motion = PushUpExercise.definition().guide.motion

    func testGuideDemonstrationCountsOncePerLoopAtAnyScaleAndProportions() {
        for (scale, upperArm, forearm, mirrored) in [(CGFloat(1), CGFloat(1), CGFloat(1), false), (0.5, 1, 1, true), (2, 1, 1, false),
                                                      (1, 0.85, 1, false), (1, 1.15, 1, true), (1, 1, 0.85, false), (1, 1, 1.15, false)] {
            let result = run(motion, scale: scale, upperArm: upperArm, forearm: forearm, mirrored: mirrored)
            XCTAssertEqual(result.reps, 3, "scale \(scale), upper \(upperArm), forearm \(forearm), mirrored \(mirrored)")
            XCTAssertTrue(result.forms.allSatisfy { $0.flags.isEmpty }, "The demonstration raises no cues: \(result.forms)")
        }
    }

    func testShallowPushUpDoesNotCountAndAsksToGoLower() {
        let result = run(variant([ArmAngles(upperArmElevation: -45, forearmElevation: -135)]))
        XCTAssertEqual(result.reps, 0)
        XCTAssertEqual(result.forms.count, 3)
        XCTAssertTrue(result.forms.allSatisfy { $0.flags == [.pushUpLower] })
    }

    func testFastLoweringAsksForControl() {
        var keyframes = motion.keyframes
        keyframes[1].moveDuration = 0.5
        let result = run(ArmMotion(keyframes: keyframes, holdsDumbbells: false))
        XCTAssertEqual(result.reps, 3)
        XCTAssertTrue(result.forms.allSatisfy { $0.flags == [.pushUpControlledLowering] }, "\(result.forms)")
    }

    func testGoingBackDownWithoutStraighteningAsksToPushAllTheWayUp() {
        let bottom = motion.topAngles
        let result = run(variant([bottom, ArmAngles(upperArmElevation: -50, forearmElevation: -130), bottom]))
        XCTAssertEqual(result.reps, 3, "Only straight arms end a rep.")
        XCTAssertEqual(result.forms.filter { $0.flags.contains(.pushUpFullExtension) }.count, 3)
    }

    func testBottomShoulderDropoutsBridgeAtAndBelowTheGapLimit() {
        for gap in [0.3, 0.7, 0.8] {
            let result = runWithGap(gap, at: .bottom)
            XCTAssertEqual(result.reps, 1, "A bottom dropout of \(gap) s counts once.")
            XCTAssertTrue(result.rejections.isEmpty, "A bottom dropout of \(gap) s is tolerated.")
            XCTAssertEqual(result.lockedAtRecovery, true, "A bottom dropout of \(gap) s keeps the locked reference.")
        }
    }

    func testBottomGapLimitRejectsLongerDropouts() {
        let result = runWithGap(0.9, at: .bottom)
        XCTAssertEqual(result.reps, 0)
        XCTAssertEqual(result.rejections.count, 1)
        XCTAssertEqual(result.lockedAtRecovery, false)
    }

    func testGapsDuringDescentAndAscentStillRejectTheAttempt() {
        for phase in [GapPhase.descent, .ascent] {
            let result = runWithGap(0.3, at: phase)
            XCTAssertEqual(result.reps, 0, "A gap during \(phase) does not count.")
            XCTAssertEqual(result.rejections.count, 1, "A gap during \(phase) is reported.")
            XCTAssertEqual(result.lockedAtRecovery, false, "A gap during \(phase) clears the reference.")
        }
    }

    func testBottomGapRejectsMovedWristsAndRulersThenCountsTheNextCleanRep() {
        let ruler = ExerciseDemoFigureView.upperArm + ExerciseDemoFigureView.forearm
        let movedWrists = runWithGap(0.3, at: .bottom,
                                     translation: CGPoint(x: ruler * 0.3, y: 0), followingCleanRep: true)
        XCTAssertEqual(movedWrists.rejections.count, 1)
        XCTAssertEqual(movedWrists.lockedAtRecovery, false)
        XCTAssertEqual(movedWrists.reps, 1, "A clean rep counts after translated hands reacquire the start.")

        let movedRuler = runWithGap(0.3, at: .bottom, scale: 0.7, followingCleanRep: true)
        XCTAssertEqual(movedRuler.rejections.count, 1)
        XCTAssertEqual(movedRuler.lockedAtRecovery, false)
        XCTAssertEqual(movedRuler.reps, 1, "A clean rep counts after a scaled ruler reacquires the start.")
    }

    func testBottomGapChecksBothSidesOfWristAndRulerStabilityLimits() {
        let ruler = ExerciseDemoFigureView.upperArm + ExerciseDemoFigureView.forearm
        for (shift, shouldBridge) in [(CGFloat(0.14), true), (0.16, false)] {
            let result = runWithGap(0.3, at: .bottom,
                                    translation: CGPoint(x: ruler * shift, y: 0))
            XCTAssertEqual(result.lockedAtRecovery, shouldBridge, "Wrist shift \(shift) of the ruler.")
        }
        for (scale, shouldBridge) in [(CGFloat(0.82), true), (0.78, false)] {
            let result = runWithGap(0.3, at: .bottom, scale: scale)
            XCTAssertEqual(result.lockedAtRecovery, shouldBridge, "Ruler scale \(scale).")
        }
    }

    func testEightCleanPushUpsStillCountEight() {
        XCTAssertEqual(run(motion, loops: 8).reps, 8)
    }

    @MainActor
    func testPlantedHandsAtBottomEdgeStillCountRep() {
        let estimated = runOffscreen(completeEdges: true)
        XCTAssertEqual(estimated, 1)
        XCTAssertEqual(runOffscreen(completeEdges: false), 0)
    }

    // MARK: - Helpers

    /// Up, then each pose in turn (with 0.3 s holds), then up.
    private func variant(_ poses: [ArmAngles]) -> ArmMotion {
        var keyframes = [ArmKeyframe(angles: motion.startAngles, moveDuration: 0, holdDuration: 1.0, stepIndex: 0)]
        for pose in poses { keyframes.append(ArmKeyframe(angles: pose, moveDuration: 1.2, holdDuration: 0.3, stepIndex: 1)) }
        keyframes.append(ArmKeyframe(angles: motion.startAngles, moveDuration: 1.0, holdDuration: 0, stepIndex: 2))
        return ArmMotion(keyframes: keyframes, holdsDumbbells: false)
    }

    private struct Run {
        var reps = 0
        var forms: [RepForm] = []
        var rejections: [RepRejection] = []
        var lockedAtRecovery: Bool?
    }

    private enum GapPhase: Equatable {
        case bottom
        case descent
        case ascent
    }

    /// Samples `motion` at 10 Hz for three loops on the floor-view figure, with hands planted and the
    /// shoulders placed by the arm pose, at the given scale and arm proportions.
    private func run(_ motion: ArmMotion, scale: CGFloat = 1, upperArm: CGFloat = 1, forearm: CGFloat = 1,
                     mirrored: Bool = false, loops: Int = 3) -> Run {
        let analyzer = PushUpAnalyzer(epoch: 1)
        var result = Run()
        for index in 0..<(Int(motion.duration * 10) * loops) {
            let time = Double(index) / 10
            let angles = motion.sample(at: time).angles
            var joints: [LandmarkType: CGPoint] = [:]
            for side in BodySide.allCases {
                guard let hand = ExerciseDemoFigureView.floorHands[side] else { continue }
                let arm = ArmMotion.place(shoulder: .zero, outward: side == .left ? 1 : -1,
                                          upperArm: ExerciseDemoFigureView.upperArm * upperArm,
                                          forearm: ExerciseDemoFigureView.forearm * forearm, angles: angles)
                let shoulder = CGPoint(x: hand.x - arm.wrist.x, y: hand.y - arm.wrist.y)
                joints[side.shoulder] = shoulder
                joints[side.elbow] = CGPoint(x: shoulder.x + arm.elbow.x, y: shoulder.y + arm.elbow.y)
                joints[side.wrist] = hand
            }
            let landmarks = Dictionary(uniqueKeysWithValues: joints.map { type, point in
                let x = mirrored ? 300 - point.x : point.x
                return (type, Landmark(type: type, normalizedLocation: .zero,
                                       imageLocation: CGPoint(x: x * scale + 300, y: point.y * scale + 200), confidence: 0.9))
            })
            let analysis = analyzer.process(PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920),
                                                      timestamp: time), counting: true)
            result.reps += analysis.repEvents.count
            result.forms += analysis.repForms
        }
        return result
    }

    private func runWithGap(_ gap: TimeInterval, at phase: GapPhase, translation: CGPoint = .zero,
                            scale: CGFloat = 1, followingCleanRep: Bool = false) -> Run {
        let analyzer = PushUpAnalyzer(epoch: 2)
        var result = Run()
        let up = motion.sample(at: 0).angles
        let middle = motion.sample(at: 1.75).angles
        let down = motion.sample(at: 2.5).angles
        func feed(_ angles: ArmAngles, _ time: TimeInterval) {
            _ = process(angles, at: time, analyzer: analyzer, result: &result)
        }
        func feedTransformed(_ angles: ArmAngles, _ time: TimeInterval, translation: CGPoint, scale: CGFloat) {
            _ = process(angles, at: time, analyzer: analyzer, result: &result,
                        translation: translation, scale: scale)
        }

        feed(up, 0)
        feed(up, 0.1)
        let gapStart: TimeInterval
        let beforeGap: ArmAngles
        switch phase {
        case .bottom:
            feed(middle, 0.2)
            feed(down, 0.3)
            gapStart = 0.3
            beforeGap = down
        case .descent:
            feed(middle, 0.2)
            gapStart = 0.2
            beforeGap = middle
        case .ascent:
            feed(middle, 0.2)
            feed(down, 0.3)
            feed(down, 0.4)
            feed(middle, 0.5)
            gapStart = 0.5
            beforeGap = middle
        }

        let resume = gapStart + gap
        var missing = gapStart + 0.1
        while missing < resume - 0.000_001 {
            _ = process(beforeGap, at: missing, analyzer: analyzer, result: &result,
                        shoulderConfidence: 0.2, counting: false)
            missing += 0.1
        }
        let recovery = process(phase == .bottom ? down : middle, at: resume, analyzer: analyzer, result: &result,
                              translation: translation, scale: scale)
        result.lockedAtRecovery = recovery.thresholds.values.contains(where: \.isLocked)

        switch phase {
        case .bottom:
            feedTransformed(down, resume + 0.1, translation: translation, scale: scale)
            feedTransformed(middle, resume + 0.2, translation: translation, scale: scale)
            feedTransformed(up, resume + 0.3, translation: translation, scale: scale)
            feedTransformed(up, resume + 0.4, translation: translation, scale: scale)
            if followingCleanRep {
                feedTransformed(up, resume + 0.5, translation: translation, scale: scale)
                feedTransformed(up, resume + 0.6, translation: translation, scale: scale)
                feedTransformed(middle, resume + 0.7, translation: translation, scale: scale)
                feedTransformed(middle, resume + 0.8, translation: translation, scale: scale)
                feedTransformed(down, resume + 0.9, translation: translation, scale: scale)
                feedTransformed(down, resume + 1.0, translation: translation, scale: scale)
                feedTransformed(middle, resume + 1.1, translation: translation, scale: scale)
                feedTransformed(middle, resume + 1.2, translation: translation, scale: scale)
                feedTransformed(middle, resume + 1.3, translation: translation, scale: scale)
                feedTransformed(up, resume + 1.4, translation: translation, scale: scale)
                feedTransformed(up, resume + 1.5, translation: translation, scale: scale)
            }
        case .descent:
            feed(middle, resume + 0.1)
            feed(down, resume + 0.2)
            feed(down, resume + 0.3)
            feed(middle, resume + 0.4)
            feed(up, resume + 0.5)
            feed(up, resume + 0.6)
        case .ascent:
            feed(up, resume + 0.1)
            feed(up, resume + 0.2)
        }
        return result
    }

    private func process(_ angles: ArmAngles, at time: TimeInterval, analyzer: PushUpAnalyzer, result: inout Run,
                         shoulderConfidence: Double = 0.9, translation: CGPoint = .zero, scale: CGFloat = 1,
                         counting: Bool = true) -> ExerciseAnalysis {
        let analysis = analyzer.process(pushUpFrame(angles, at: time, shoulderConfidence: shoulderConfidence,
                                                    translation: translation, scale: scale), counting: counting)
        result.reps += analysis.repEvents.count
        result.forms += analysis.repForms
        result.rejections += analysis.rejections
        return analysis
    }

    private func pushUpFrame(_ angles: ArmAngles, at time: TimeInterval, shoulderConfidence: Double = 0.9,
                             translation: CGPoint = .zero, scale: CGFloat = 1) -> PoseFrame {
        var joints: [LandmarkType: (CGPoint, Double)] = [:]
        for side in BodySide.allCases {
            guard let hand = ExerciseDemoFigureView.floorHands[side] else { continue }
            let arm = ArmMotion.place(shoulder: .zero, outward: side == .left ? 1 : -1,
                                      upperArm: ExerciseDemoFigureView.upperArm,
                                      forearm: ExerciseDemoFigureView.forearm, angles: angles)
            let shoulder = CGPoint(x: hand.x - arm.wrist.x, y: hand.y - arm.wrist.y)
            let elbow = CGPoint(x: shoulder.x + arm.elbow.x, y: shoulder.y + arm.elbow.y)
            func point(_ location: CGPoint) -> CGPoint {
                CGPoint(x: (location.x - hand.x) * scale + hand.x + translation.x + 300,
                        y: (location.y - hand.y) * scale + hand.y + translation.y + 200)
            }
            joints[side.shoulder] = (point(shoulder), shoulderConfidence)
            joints[side.elbow] = (point(elbow), 0.9)
            joints[side.wrist] = (point(hand), 0.9)
        }
        let landmarks = Dictionary(uniqueKeysWithValues: joints.map { type, value in
            (type, Landmark(type: type, normalizedLocation: .zero, imageLocation: value.0,
                            confidence: value.1))
        })
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920), timestamp: time)
    }

    @MainActor
    private func runOffscreen(completeEdges: Bool) -> Int {
        let exercise = PushUpExercise.definition()
        let motion = exercise.guide.motion
        let analyzer = exercise.makeAnalyzer(1)
        var estimator = OffscreenJointEstimator(joints: exercise.focusJoints, plantedJoints: exercise.plantedJoints)
        var reps = 0
        for index in 0...Int(motion.duration * 10) {
            let time = Double(index) / 10
            let angles = motion.sample(at: time).angles
            var joints: [LandmarkType: CGPoint] = [:]
            for side in BodySide.allCases {
                guard let hand = ExerciseDemoFigureView.floorHands[side] else { continue }
                let arm = ArmMotion.place(shoulder: .zero, outward: side == .left ? 1 : -1,
                                          upperArm: ExerciseDemoFigureView.upperArm,
                                          forearm: ExerciseDemoFigureView.forearm, angles: angles)
                let shoulder = CGPoint(x: hand.x - arm.wrist.x, y: hand.y - arm.wrist.y)
                joints[side.shoulder] = shoulder
                joints[side.elbow] = CGPoint(x: shoulder.x + arm.elbow.x, y: shoulder.y + arm.elbow.y)
                joints[side.wrist] = hand
            }
            let landmarks = Dictionary(uniqueKeysWithValues: joints.compactMap { type, point -> (LandmarkType, Landmark)? in
                if [.leftWrist, .rightWrist].contains(type), (2.4...3.8).contains(time) { return nil }
                let pixel = CGPoint(x: point.x + 300, y: point.y + 1490)
                return (type, Landmark(type: type,
                                       normalizedLocation: CoordinateConverter.imagePixelToNormalized(
                                        pixel: pixel, imageWidth: 1080, imageHeight: 1920),
                                       imageLocation: pixel,
                                       confidence: 0.9))
            })
            let raw = PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920), timestamp: time)
            let completed = completeEdges ? estimator.complete(raw) : raw
            reps += analyzer.process(completed, counting: true).repEvents.count
        }
        return reps
    }

    // MARK: - Phone distance

    func testAPhoneTooCloseAsksToMoveItFartherWithoutBlockingTracking() {
        let pushUp = PushUpExercise.definition()
        var framing = Self.framing(for: pushUp)
        // Shoulders across 36% of the frame: recordings lost the body at the bottom of every rep from 34%.
        var status = framing.evaluate(Self.plank(shoulderSpan: 0.36, at: 0))
        XCTAssertEqual(status.guidance, .movePhoneFartherFloor)
        status = framing.evaluate(Self.plank(shoulderSpan: 0.36, at: 0.7))
        XCTAssertTrue(status.isReliable, "Too close holds setup but never stops counting mid-set.")
        XCTAssertEqual(status.guidance, .movePhoneFartherFloor)
        XCTAssertEqual(FramingGuidance.movePhoneFartherFloor.spokenText,
                       "Move the phone farther from your hands, so you stay in view at the bottom.")
    }

    func testAPhoneFarEnoughAwayGivesNoDistanceGuidance() {
        var framing = Self.framing(for: PushUpExercise.definition())
        XCTAssertNil(framing.evaluate(Self.plank(shoulderSpan: 0.28, at: 0)).guidance)
    }

    func testTheDistanceWarningClearsOnlyWellBelowTheLimit() {
        var framing = Self.framing(for: PushUpExercise.definition())
        let spans: [(CGFloat, FramingGuidance?)] = [(0.33, .movePhoneFartherFloor), (0.31, .movePhoneFartherFloor),
                                                     (0.29, nil), (0.31, nil), (0.33, .movePhoneFartherFloor)]
        for (index, (span, expected)) in spans.enumerated() {
            XCTAssertEqual(framing.evaluate(Self.plank(shoulderSpan: span, at: Double(index) / 10)).guidance, expected,
                           "span \(span)")
        }
    }

    func testOtherExercisesIgnoreShoulderSpan() {
        let squat = AirSquatExercise.definition()
        XCTAssertNil(squat.maximumShoulderSpan)
        XCTAssertEqual(PushUpExercise.definition().maximumShoulderSpan, 0.32)
    }

    private static func framing(for exercise: ExerciseDefinition) -> FramingEvaluator {
        FramingEvaluator(requiredJoints: exercise.requiredJoints, anyOfRequiredJoints: exercise.anyOfRequiredJoints,
                         headroomArmLengths: exercise.headroomArmLengths, sideroomArmLengths: exercise.sideroomArmLengths,
                         maximumShoulderSpan: exercise.maximumShoulderSpan, cameraView: exercise.cameraView)
    }

    /// A centered top-of-plank pose seen from the floor, straight arms, with the shoulders `shoulderSpan` of the width apart.
    private static func plank(shoulderSpan: CGFloat, at time: TimeInterval) -> PoseFrame {
        let width: CGFloat = 1080, height: CGFloat = 1920
        let half = shoulderSpan * width / 2
        let points: [LandmarkType: CGPoint] = [
            .leftShoulder: CGPoint(x: 540 + half, y: 900), .rightShoulder: CGPoint(x: 540 - half, y: 900),
            .leftElbow: CGPoint(x: 540 + half, y: 1150), .rightElbow: CGPoint(x: 540 - half, y: 1150),
            .leftWrist: CGPoint(x: 540 + half, y: 1400), .rightWrist: CGPoint(x: 540 - half, y: 1400)
        ]
        let landmarks = Dictionary(uniqueKeysWithValues: points.map { type, point in
            (type, Landmark(type: type,
                            normalizedLocation: CoordinateConverter.imagePixelToNormalized(pixel: point, imageWidth: width,
                                                                                         imageHeight: height),
                            imageLocation: point, confidence: 0.9))
        })
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: width, imageHeight: height), timestamp: time)
    }
}
