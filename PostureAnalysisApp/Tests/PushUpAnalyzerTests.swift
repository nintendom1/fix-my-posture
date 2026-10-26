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
    }

    /// Samples `motion` at 10 Hz for three loops on the floor-view figure, with hands planted and the
    /// shoulders placed by the arm pose, at the given scale and arm proportions.
    private func run(_ motion: ArmMotion, scale: CGFloat = 1, upperArm: CGFloat = 1, forearm: CGFloat = 1,
                     mirrored: Bool = false) -> Run {
        let analyzer = PushUpAnalyzer(epoch: 1)
        var result = Run()
        for index in 0..<(Int(motion.duration * 10) * 3) {
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
