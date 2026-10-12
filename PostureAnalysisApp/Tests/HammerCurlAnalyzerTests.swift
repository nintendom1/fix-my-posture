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
                     sway: (TimeInterval) -> CGFloat = { _ in 0 }) -> Run {
        let analyzer = HammerCurlAnalyzer(epoch: 1)
        var result = Run()
        let samples = Int((motion.duration * 3 + rightDelay) * 10)
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
            let frame = PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920), timestamp: time)
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
