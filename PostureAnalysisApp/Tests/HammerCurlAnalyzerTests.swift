import XCTest
@testable import PostureAnalysisApp

final class HammerCurlAnalyzerTests: XCTestCase {
    private let motion = HammerCurlExercise.definition().guide.motion

    @MainActor
    func testGuideDemonstrationCountsEachArmOncePerLoopAtAnyScaleAndProportions() {
        for (scale, upperArm, forearm) in [(CGFloat(1), CGFloat(1), CGFloat(1)), (0.5, 1, 1), (2, 1, 1),
                                           (1, 1, 0.85), (1, 1, 1.15), (1, 0.85, 1), (1, 1.15, 1)] {
            let result = run(motion, scale: scale, upperArm: upperArm, forearm: forearm)
            XCTAssertEqual(result.reps[.left], 3, "scale \(scale), upper \(upperArm), forearm \(forearm)")
            XCTAssertEqual(result.reps[.right], 3, "scale \(scale), upper \(upperArm), forearm \(forearm)")
            XCTAssertTrue(result.forms.allSatisfy { $0.flags.isEmpty }, "The demonstration raises no cues: \(result.forms)")
            XCTAssertTrue(result.signals.allSatisfy(\.isEmpty))
        }
    }

    @MainActor
    func testAlternatingArmsEachCount() {
        // The right arm runs half a loop behind, so the arms take turns.
        let result = run(motion, rightDelay: motion.duration / 2)
        XCTAssertEqual(result.reps[.left], 3)
        XCTAssertEqual(result.reps[.right], 3)
        XCTAssertTrue(result.forms.allSatisfy { $0.flags.isEmpty })
    }

    @MainActor
    func testCurlingAgainWithoutHangingStraightDoesNotCountExtraAndAsksToStraighten() {
        let midway = ArmAngles(upperArmElevation: -82, forearmElevation: -20)
        let recurl = ArmMotion(keyframes: [
            ArmKeyframe(angles: motion.startAngles, moveDuration: 0, holdDuration: 1.0, stepIndex: 0),
            ArmKeyframe(angles: motion.topAngles, moveDuration: 1.0, holdDuration: 0.4, stepIndex: 1),
            ArmKeyframe(angles: midway, moveDuration: 0.8, holdDuration: 0.2, stepIndex: 2),
            ArmKeyframe(angles: motion.topAngles, moveDuration: 0.8, holdDuration: 0.4, stepIndex: 1),
            ArmKeyframe(angles: motion.startAngles, moveDuration: 1.5, holdDuration: 0, stepIndex: 2)
        ], forearmPlane: .sagittal)
        let result = run(recurl)
        XCTAssertEqual(result.reps[.left], 3, "Only the full return to hanging counts.")
        XCTAssertEqual(result.forms.filter { $0.flags.contains(.curlStraightenAtBottom) }.count, 6)
    }

    @MainActor
    func testHalfCurlDoesNotCountAndAsksToCurlAllTheWayUp() {
        let half = ArmMotion(keyframes: [
            ArmKeyframe(angles: motion.startAngles, moveDuration: 0, holdDuration: 1.0, stepIndex: 0),
            ArmKeyframe(angles: ArmAngles(upperArmElevation: -82, forearmElevation: 0), moveDuration: 1.0, holdDuration: 0.4, stepIndex: 1),
            ArmKeyframe(angles: motion.startAngles, moveDuration: 1.5, holdDuration: 0, stepIndex: 2)
        ], forearmPlane: .sagittal)
        let result = run(half)
        XCTAssertEqual(result.reps[.left] ?? 0, 0)
        XCTAssertEqual(result.forms.count, 6, "Each arm's attempt is judged.")
        XCTAssertTrue(result.forms.allSatisfy { $0.flags == [.curlFullRange] })
    }

    @MainActor
    func testFlaredElbowsAndSwayRaiseSignalsButSwayNeedsHips() {
        // From 4.5 s the elbows drift outward by about a third of shoulder width.
        let flared = run(motion, elbowFlare: { $0 >= 4.5 ? 32 : 0 })
        XCTAssertFalse(flared.signals[..<45].contains { $0.contains(.curlElbowsIn) })
        XCTAssertTrue(flared.signals[45...].allSatisfy { $0.contains(.curlElbowsIn) })
        XCTAssertEqual(flared.reps[.left], 3, "Form never affects counting.")

        // From 4.5 s the upper body leans about 0.43 upper-arm lengths sideways over the hips.
        let swaying = run(motion, sway: { $0 >= 4.5 ? 30 : 0 })
        XCTAssertTrue(swaying.signals[45...].allSatisfy { $0.contains(.curlBodyStill) })
        XCTAssertFalse(run(motion, hips: false, sway: { $0 >= 4.5 ? 30 : 0 }).signals.contains { $0.contains(.curlBodyStill) })
    }

    @MainActor
    func testEstimatedWristInvalidatesFormAttemptWithoutLosingRep() {
        let midway = ArmAngles(upperArmElevation: -82, forearmElevation: -20)
        let recurl = ArmMotion(keyframes: [
            ArmKeyframe(angles: motion.startAngles, moveDuration: 0, holdDuration: 1.0, stepIndex: 0),
            ArmKeyframe(angles: motion.topAngles, moveDuration: 1.0, holdDuration: 0.4, stepIndex: 1),
            ArmKeyframe(angles: midway, moveDuration: 0.8, holdDuration: 0.2, stepIndex: 2),
            ArmKeyframe(angles: motion.topAngles, moveDuration: 0.8, holdDuration: 0.4, stepIndex: 1),
            ArmKeyframe(angles: motion.startAngles, moveDuration: 1.5, holdDuration: 0, stepIndex: 2)
        ], forearmPlane: .sagittal)

        let observed = run(recurl, loops: 1)
        XCTAssertEqual(observed.reps[.left], 1)
        XCTAssertTrue(observed.forms.contains { $0.flags.contains(.curlStraightenAtBottom) })

        let estimated = run(recurl, loops: 1, estimatedDuring: 1.5...4.5)
        XCTAssertEqual(estimated.reps[.left], 1)
        XCTAssertFalse(estimated.forms.contains { $0.flags.contains(.curlStraightenAtBottom) })
    }

    // MARK: - Camera-view hand-off

    @MainActor
    func testReportsEachArmPastTheTopUntilItsReturnIsCreditedOrCountingStops() {
        let analyzer = HammerCurlAnalyzer(epoch: 1)
        var index = 0
        func feed(_ left: Double?, _ right: Double?, counting: Bool = true) -> ExerciseAnalysis {
            defer { index += 1 }
            return analyzer.process(curlFrame(left: left, right: right, at: Double(index) / 10), counting: counting)
        }

        for _ in 0..<5 { _ = feed(-90, -90) }
        XCTAssertNil(analyzer.attemptInProgress(), "Hanging at the start is no attempt.")
        _ = feed(0, -90)
        XCTAssertNil(analyzer.attemptInProgress(), "A curl that hasn't reached the top doesn't carry.")
        _ = feed(50, -90)
        _ = feed(50, -90)
        XCTAssertEqual(analyzer.attemptInProgress(),
                       RepAttemptInProgress(movementStart: 0.4, reachedEnd: 0.7, sides: [.left]))

        _ = feed(50, 50)
        _ = feed(50, 50)
        XCTAssertEqual(analyzer.attemptInProgress(),
                       RepAttemptInProgress(movementStart: 0.4, reachedEnd: 0.9, sides: [.left, .right]),
                       "The earliest start and the latest top span both arms.")

        // The right arm hides behind the body, as the far arm does during a turn; its curl still carries.
        for _ in 0..<4 { _ = feed(50, nil) }
        XCTAssertEqual(analyzer.attemptInProgress()?.sides, [.left, .right])

        _ = feed(-90, nil)
        let credited = feed(-90, nil)
        XCTAssertEqual(credited.repEvents.map(\.sides), [[.left]])
        XCTAssertEqual(analyzer.attemptInProgress(),
                       RepAttemptInProgress(movementStart: 0.7, reachedEnd: 0.9, sides: [.right]),
                       "A credited return leaves only the other arm's curl.")

        _ = feed(-90, nil, counting: false)
        XCTAssertNil(analyzer.attemptInProgress(), "Counting stopped while the arm was hidden, so its curl is lost.")
    }

    @MainActor
    func testACountingStopDropsAVisibleArmsCurlPastTheTop() {
        let analyzer = HammerCurlAnalyzer(epoch: 1)
        for (index, elevation) in [-90.0, -90, -90, 50, 50].enumerated() {
            _ = analyzer.process(curlFrame(left: elevation, right: -90, at: Double(index) / 10), counting: true)
        }
        XCTAssertEqual(analyzer.attemptInProgress()?.sides, [.left])

        _ = analyzer.process(curlFrame(left: 50, right: -90, at: 0.5), counting: false)
        _ = analyzer.process(curlFrame(left: 50, right: -90, at: 0.6), counting: true)

        XCTAssertNil(analyzer.attemptInProgress())
    }

    @MainActor
    func testResumedArmsEachCountOnceWhenTheyHangStraight() {
        let analyzer = HammerCurlAnalyzer(epoch: 2)
        // This view's warm-up saw only the top, never the curl's start.
        for index in 0..<4 {
            _ = analyzer.process(curlFrame(left: 50, right: 50, at: Double(index) / 10), counting: true)
        }
        XCTAssertNil(analyzer.attemptInProgress())

        let carried = RepAttemptInProgress(movementStart: -1, reachedEnd: -0.5, sides: [.left, .right])
        analyzer.resume(carried)
        XCTAssertEqual(analyzer.attemptInProgress(), carried)

        // The left arm lowers first, then the right.
        let lowering: [(left: Double, right: Double)] = [(0, 50), (-90, 50), (-90, 50), (-90, 0), (-90, -90)]
            + Array(repeating: (-90, -90), count: 11)
        var reps: [RepEvent] = []
        for (offset, pose) in lowering.enumerated() {
            let time = Double(4 + offset) / 10
            reps += analyzer.process(curlFrame(left: pose.left, right: pose.right, at: time), counting: true).repEvents
        }

        XCTAssertEqual(reps, [RepEvent(epoch: 2, timestamp: 0.6, sides: [.left]),
                              RepEvent(epoch: 2, timestamp: 0.9, sides: [.right])])
        XCTAssertNil(analyzer.attemptInProgress())
    }

    @MainActor
    func testAResumedArmAlreadyHangingSinceTheTopCountsOnTheNextCountingFrame() {
        let analyzer = HammerCurlAnalyzer(epoch: 3)
        // During the warm-up both arms come down from the top and hang straight from 0.4 s.
        for (index, elevation) in [50.0, 50, 0, -90, -90, -90].enumerated() {
            _ = analyzer.process(curlFrame(left: elevation, right: elevation, at: Double(index) / 10), counting: true)
        }

        analyzer.resume(RepAttemptInProgress(movementStart: -1, reachedEnd: 0.2, sides: [.left, .right]))
        let first = analyzer.process(curlFrame(left: -90, right: -90, at: 0.6), counting: true)
        var later: [RepEvent] = []
        for index in 7..<20 {
            later += analyzer.process(curlFrame(left: -90, right: -90, at: Double(index) / 10), counting: true).repEvents
        }

        XCTAssertEqual(first.repEvents.count, 2)
        XCTAssertEqual(Set(first.repEvents.flatMap(\.sides)), [.left, .right])
        XCTAssertTrue(first.repEvents.allSatisfy { $0.timestamp == 0.6 })
        XCTAssertTrue(later.isEmpty, "The carried curl counts once.")
    }

    @MainActor
    func testResumeKeepsAnArmsOwnCurlAndIgnoresAStartSeenBeforeTheCarriedTop() {
        let analyzer = HammerCurlAnalyzer(epoch: 4)
        // Both arms hang from 0 s. The right reaches its own top at 0.4 s; the left only half curls.
        let curl: [(left: Double, right: Double)] = Array(repeating: (-90, -90), count: 3)
            + Array(repeating: (0, 50), count: 8)
        for (index, pose) in curl.enumerated() {
            _ = analyzer.process(curlFrame(left: pose.left, right: pose.right, at: Double(index) / 10), counting: true)
        }

        analyzer.resume(RepAttemptInProgress(movementStart: 0.2, reachedEnd: 0.35, sides: [.left, .right]))
        XCTAssertEqual(analyzer.attemptInProgress(),
                       RepAttemptInProgress(movementStart: 0.2, reachedEnd: 0.4, sides: [.right]),
                       "The right arm keeps its own curl; the left saw its start before the carried top.")

        var reps: [RepEvent] = []
        for index in 11..<22 {
            reps += analyzer.process(curlFrame(left: -90, right: -90, at: Double(index) / 10), counting: true).repEvents
        }
        XCTAssertEqual(reps.map(\.sides), [[.right]])
    }

    /// A front frame with each forearm's elevation in degrees and the upper arms hanging. A nil elevation hides
    /// that arm's elbow and wrist.
    @MainActor
    private func curlFrame(left: Double?, right: Double?, at time: TimeInterval) -> PoseFrame {
        var joints = ExerciseDemoFigureView.figureJoints
        for (side, elevation) in [(BodySide.left, left), (BodySide.right, right)] {
            let other: BodySide = side == .left ? .right : .left
            guard let elevation, let shoulder = joints[side.shoulder], let otherShoulder = joints[other.shoulder] else {
                continue
            }
            let arm = ArmMotion.place(shoulder: shoulder, otherShoulder: otherShoulder,
                                      upperArm: ExerciseDemoFigureView.upperArm, forearm: ExerciseDemoFigureView.forearm,
                                      angles: ArmAngles(upperArmElevation: -85, forearmElevation: elevation),
                                      forearmPlane: .sagittal)
            joints[side.elbow] = arm.elbow
            joints[side.wrist] = arm.wrist
        }
        let landmarks = Dictionary(uniqueKeysWithValues: joints.map { type, point in
            (type, Landmark(type: type, normalizedLocation: .zero,
                            imageLocation: CGPoint(x: point.x * 3 + 200, y: point.y * 3 + 300), confidence: 0.9))
        })
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920), timestamp: time)
    }

    private struct Run {
        var reps: [BodySide: Int] = [:]
        var forms: [RepForm] = []
        var signals: [Set<CoachingCueID>] = []
    }

    /// Samples `motion` at 10 Hz for three loops (plus any right-arm delay) on the demo figure, with
    /// optional changes to scale, limb proportions, elbow position, and upper-body sway.
    @MainActor
    private func run(_ motion: ArmMotion, rightDelay: TimeInterval = 0, scale: CGFloat = 1, upperArm: CGFloat = 1,
                     forearm: CGFloat = 1, hips: Bool = true, elbowFlare: (TimeInterval) -> CGFloat = { _ in 0 },
                     sway: (TimeInterval) -> CGFloat = { _ in 0 }, loops: Int = 3,
                     estimatedDuring: ClosedRange<TimeInterval>? = nil) -> Run {
        let analyzer = HammerCurlAnalyzer(epoch: 1)
        var result = Run()
        let samples = Int((motion.duration * Double(loops) + rightDelay) * 10)
        for index in 0..<samples {
            let time = Double(index) / 10
            var joints = ExerciseDemoFigureView.figureJoints
            for side in BodySide.allCases {
                let other: BodySide = side == .left ? .right : .left
                guard let shoulder = joints[side.shoulder], let otherShoulder = joints[other.shoulder] else { continue }
                // The delayed arm hangs still until its loops begin.
                let local = side == .right ? max(0, time - rightDelay) : time
                let arm = ArmMotion.place(shoulder: shoulder, otherShoulder: otherShoulder,
                                          upperArm: ExerciseDemoFigureView.upperArm * upperArm,
                                          forearm: ExerciseDemoFigureView.forearm * forearm,
                                          angles: motion.sample(at: local).angles, forearmPlane: motion.forearmPlane)
                let outward: CGFloat = shoulder.x >= otherShoulder.x ? 1 : -1
                joints[side.elbow] = CGPoint(x: arm.elbow.x + outward * elbowFlare(time), y: arm.elbow.y)
                joints[side.wrist] = CGPoint(x: arm.wrist.x + outward * elbowFlare(time), y: arm.wrist.y)
                for joint in side.armJoints { joints[joint]?.x += sway(time) }
            }
            if !hips {
                joints[.leftHip] = nil
                joints[.rightHip] = nil
            }
            let landmarks = Dictionary(uniqueKeysWithValues: joints.map { type, point in
                (type, Landmark(type: type, normalizedLocation: .zero,
                                imageLocation: CGPoint(x: point.x * scale + 200, y: point.y * scale + 300), confidence: 0.9))
            })
            let estimated: Set<LandmarkType> = estimatedDuring?.contains(time) == true ? [.leftWrist, .rightWrist] : []
            let frame = PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920),
                                  timestamp: time, estimatedJoints: estimated)
            let analysis = analyzer.process(frame, counting: true)
            for rep in analysis.repEvents {
                for side in rep.sides { result.reps[side, default: 0] += 1 }
            }
            result.forms += analysis.repForms
            result.signals.append(analysis.formSignals)
        }
        return result
    }
}
