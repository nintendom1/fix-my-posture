import XCTest
@testable import PostureAnalysisApp

final class DumbbellRowAnalyzerTests: XCTestCase {
    private let motion = DumbbellRowExercise.definition().guide.motion

    func testGuideDemonstrationCountsOncePerLoopFromEitherSideAtAnyScaleAndProportions() {
        for (scale, upperArm, forearm, mirrored, rightArm) in [(CGFloat(1), CGFloat(1), CGFloat(1), false, false),
                                                                (0.5, 1, 1, true, false), (2, 1, 1, false, true),
                                                                (1, 0.85, 1, true, true), (1, 1.15, 1, false, false),
                                                                (1, 1, 0.85, false, false), (1, 1, 1.15, true, false)] {
            let result = run(motion, scale: scale, upperArm: upperArm, forearm: forearm, mirrored: mirrored, rightArm: rightArm)
            let label = "scale \(scale), upper \(upperArm), forearm \(forearm), mirrored \(mirrored), right \(rightArm)"
            XCTAssertEqual(result.reps, 3, label)
            XCTAssertTrue(result.forms.allSatisfy { $0.flags.isEmpty }, "The demonstration raises no cues: \(result.forms)")
            XCTAssertTrue(result.signals.allSatisfy(\.isEmpty), label)
        }
    }

    func testHalfPullDoesNotCountAndAsksToPullHigher() {
        let half = ArmMotion(keyframes: [
            ArmKeyframe(angles: motion.startAngles, moveDuration: 0, holdDuration: 1.0, stepIndex: 0),
            ArmKeyframe(angles: ArmAngles(upperArmElevation: 215, forearmElevation: 270), moveDuration: 1.0, holdDuration: 0.4, stepIndex: 1),
            ArmKeyframe(angles: motion.startAngles, moveDuration: 1.5, holdDuration: 0, stepIndex: 2)
        ], torsoPitch: 50)
        let result = run(half)
        XCTAssertEqual(result.reps, 0)
        XCTAssertEqual(result.forms.count, 3)
        XCTAssertTrue(result.forms.allSatisfy { $0.flags.contains(.rowPullHigher) })
    }

    func testFastLoweringAsksForControl() {
        var keyframes = motion.keyframes
        keyframes[2].moveDuration = 0.5
        keyframes[2].holdDuration = 0.5
        let result = run(ArmMotion(keyframes: keyframes, torsoPitch: 50))
        XCTAssertEqual(result.reps, 3)
        XCTAssertTrue(result.forms.allSatisfy { $0.flags == [.rowControlledLowering] }, "\(result.forms)")
    }

    func testPullingAgainFromMidwayAsksToLowerAllTheWay() {
        let midway = ArmAngles(upperArmElevation: 225, forearmElevation: 270)
        let again = ArmMotion(keyframes: [
            ArmKeyframe(angles: motion.startAngles, moveDuration: 0, holdDuration: 1.0, stepIndex: 0),
            ArmKeyframe(angles: motion.topAngles, moveDuration: 1.0, holdDuration: 0.4, stepIndex: 1),
            ArmKeyframe(angles: midway, moveDuration: 0.8, holdDuration: 0.2, stepIndex: 2),
            ArmKeyframe(angles: motion.topAngles, moveDuration: 0.8, holdDuration: 0.4, stepIndex: 1),
            ArmKeyframe(angles: motion.startAngles, moveDuration: 1.5, holdDuration: 0, stepIndex: 2)
        ], torsoPitch: 50)
        let result = run(again)
        XCTAssertEqual(result.reps, 3, "Only hanging straight again ends a rep.")
        XCTAssertEqual(result.forms.filter { $0.flags.contains(.rowStraighten) }.count, 3)
    }

    func testBackTippingRaisesSignalOnlyWithHip() {
        let tipping = run(motion, extraPitch: { $0 >= 4.5 ? 25 : 0 })
        XCTAssertFalse(tipping.signals[..<45].contains { $0.contains(.rowBackStill) })
        XCTAssertTrue(tipping.signals[46...].allSatisfy { $0.contains(.rowBackStill) })
        XCTAssertFalse(run(motion, hip: false, extraPitch: { $0 >= 4.5 ? 25 : 0 }).signals.contains { $0.contains(.rowBackStill) })
    }

    func testEstimatedWristInvalidatesFormAttemptWithoutLosingRep() {
        let midway = ArmAngles(upperArmElevation: 225, forearmElevation: 270)
        let recurl = ArmMotion(keyframes: [
            ArmKeyframe(angles: motion.startAngles, moveDuration: 0, holdDuration: 1.0, stepIndex: 0),
            ArmKeyframe(angles: motion.topAngles, moveDuration: 1.0, holdDuration: 0.4, stepIndex: 1),
            ArmKeyframe(angles: midway, moveDuration: 0.8, holdDuration: 0.2, stepIndex: 2),
            ArmKeyframe(angles: motion.topAngles, moveDuration: 0.8, holdDuration: 0.4, stepIndex: 1),
            ArmKeyframe(angles: motion.startAngles, moveDuration: 1.5, holdDuration: 0, stepIndex: 2)
        ], torsoPitch: 50)

        let observed = run(recurl, loops: 1)
        XCTAssertEqual(observed.reps, 1)
        XCTAssertTrue(observed.forms.contains { $0.flags.contains(.rowStraighten) })

        let estimated = run(recurl, loops: 1, estimatedDuring: 1.5...4.5)
        XCTAssertEqual(estimated.reps, 1)
        XCTAssertFalse(estimated.forms.contains { $0.flags.contains(.rowStraighten) })
    }

    private struct Run {
        var reps = 0
        var forms: [RepForm] = []
        var signals: [Set<CoachingCueID>] = []
    }

    /// Samples `motion` at 10 Hz for three loops on the bent-over side figure, with optional scale, arm
    /// proportions, facing direction, the right arm instead of the left, and extra forward lean.
    private func run(_ motion: ArmMotion, scale: CGFloat = 1, upperArm: CGFloat = 1, forearm: CGFloat = 1,
                     mirrored: Bool = false, rightArm: Bool = false, hip: Bool = true,
                     extraPitch: (TimeInterval) -> Double = { _ in 0 }, loops: Int = 3,
                     estimatedDuring: ClosedRange<TimeInterval>? = nil) -> Run {
        let analyzer = DumbbellRowAnalyzer(epoch: 1)
        var result = Run()
        for index in 0..<(Int(motion.duration * Double(loops) * 10)) {
            let time = Double(index) / 10
            let angles = motion.sample(at: time).angles
            var joints = ExerciseDemoFigureView.pose(for: angles, cameraView: .side,
                                                     torsoPitch: motion.torsoPitch + extraPitch(time)).jointLocations
            if let shoulder = joints[.leftShoulder] {
                let arm = ArmMotion.place(shoulder: shoulder, outward: 1, upperArm: ExerciseDemoFigureView.upperArm * upperArm,
                                          forearm: ExerciseDemoFigureView.forearm * forearm, angles: angles)
                joints[.leftElbow] = arm.elbow
                joints[.leftWrist] = arm.wrist
            }
            if !hip { joints[.leftHip] = nil }
            if rightArm {
                for pair in [(LandmarkType.leftShoulder, LandmarkType.rightShoulder), (.leftElbow, .rightElbow), (.leftWrist, .rightWrist),
                             (.leftHip, .rightHip), (.leftKnee, .rightKnee), (.leftAnkle, .rightAnkle)] {
                    joints[pair.1] = joints.removeValue(forKey: pair.0)
                }
            }
            let landmarks = Dictionary(uniqueKeysWithValues: joints.map { type, point in
                let x = mirrored ? 300 - point.x : point.x
                return (type, Landmark(type: type, normalizedLocation: .zero,
                                       imageLocation: CGPoint(x: x * scale + 300, y: point.y * scale + 400), confidence: 0.9))
            })
            let estimated: Set<LandmarkType> = estimatedDuring?.contains(time) == true ? [.leftWrist] : []
            let frame = PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920),
                                  timestamp: time, estimatedJoints: estimated)
            let analysis = analyzer.process(frame, counting: true)
            result.reps += analysis.repEvents.count
            result.forms += analysis.repForms
            result.signals.append(analysis.formSignals)
        }
        return result
    }
}
