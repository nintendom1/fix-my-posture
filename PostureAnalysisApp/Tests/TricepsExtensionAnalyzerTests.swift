import XCTest
@testable import PostureAnalysisApp

final class TricepsExtensionAnalyzerTests: XCTestCase {
    private let definition = TricepsExtensionExercise.definition()
    private var motion: ArmMotion { definition.guide.motion }

    @MainActor
    func testGuideDemonstrationCountsOncePerLoopFromEitherSideAtAnyScaleAndProportions() {
        for (scale, upperArm, forearm, mirrored, rightArm) in [(CGFloat(1), CGFloat(1), CGFloat(1), false, false),
                                                                (0.5, 1, 1, true, false), (2, 1, 1, false, true),
                                                                (1, 1, 0.85, true, true), (1, 1, 1.15, false, false),
                                                                (1, 0.85, 1, false, false), (1, 1.15, 1, true, false)] {
            let result = run(motion, scale: scale, upperArm: upperArm, forearm: forearm, mirrored: mirrored, rightArm: rightArm)
            let label = "scale \(scale), upper \(upperArm), forearm \(forearm), mirrored \(mirrored), right \(rightArm)"
            XCTAssertEqual(result.reps, 3, label)
            XCTAssertTrue(result.forms.allSatisfy { $0.flags.isEmpty }, "The demonstration raises no cues: \(result.forms)")
            XCTAssertTrue(result.signals.allSatisfy(\.isEmpty), label)
        }
    }

    @MainActor
    func testHalfExtensionDoesNotCountAndAsksToStraighten() {
        let result = run(variant(top: ArmAngles(upperArmElevation: 85, forearmElevation: 150)))
        XCTAssertEqual(result.reps, 0)
        XCTAssertEqual(result.forms.count, 3)
        XCTAssertTrue(result.forms.allSatisfy { $0.flags.contains(.tricepsFullExtension) })
    }

    @MainActor
    func testFastLoweringAsksForControl() {
        var keyframes = motion.keyframes
        keyframes[2].moveDuration = 0.5
        keyframes[2].holdDuration = 0.5
        let result = run(ArmMotion(keyframes: keyframes))
        XCTAssertEqual(result.reps, 3)
        XCTAssertTrue(result.forms.allSatisfy { $0.flags == [.tricepsControlledLowering] }, "\(result.forms)")
    }

    @MainActor
    func testExtendingAgainFromMidwayAsksToLowerBehindHead() {
        let midway = ArmAngles(upperArmElevation: 85, forearmElevation: 170)
        let again = ArmMotion(keyframes: [
            ArmKeyframe(angles: motion.startAngles, moveDuration: 0, holdDuration: 1.0, stepIndex: 0),
            ArmKeyframe(angles: motion.topAngles, moveDuration: 1.0, holdDuration: 0.4, stepIndex: 1),
            ArmKeyframe(angles: midway, moveDuration: 0.8, holdDuration: 0.2, stepIndex: 2),
            ArmKeyframe(angles: motion.topAngles, moveDuration: 0.8, holdDuration: 0.4, stepIndex: 1),
            ArmKeyframe(angles: motion.startAngles, moveDuration: 1.5, holdDuration: 0, stepIndex: 2)
        ])
        let result = run(again)
        XCTAssertEqual(result.reps, 3, "Only the full return behind the head ends a rep.")
        XCTAssertEqual(result.forms.filter { $0.flags.contains(.tricepsLowerBehindHead) }.count, 3)
    }

    @MainActor
    func testElbowsTippingForwardRaisesSignal() {
        // From 4.5 s the upper arm tips 30° forward from vertical.
        let result = run(motion, upperArmTilt: { $0 >= 4.5 ? -30 : 0 })
        XCTAssertFalse(result.signals[..<45].contains { $0.contains(.tricepsElbowsUp) })
        XCTAssertTrue(result.signals[46...].allSatisfy { $0.contains(.tricepsElbowsUp) })
        XCTAssertEqual(result.reps, 3, "Form never affects counting.")
    }

    func testSideOnFramingAcceptsEitherArmAndAsksToStandSideOn() {
        var evaluator = FramingEvaluator(requiredJoints: definition.requiredJoints, anyOfRequiredJoints: definition.anyOfRequiredJoints,
                                         headroomArmLengths: nil, cameraView: .side)
        let rightArmOnly: [LandmarkType: CGPoint] = [.nose: CGPoint(x: 560, y: 600), .rightShoulder: CGPoint(x: 540, y: 700),
                                                     .rightElbow: CGPoint(x: 545, y: 500), .rightWrist: CGPoint(x: 500, y: 650),
                                                     .rightHip: CGPoint(x: 540, y: 1100)]
        _ = evaluator.evaluate(frame(rightArmOnly, at: 0))
        XCTAssertTrue(evaluator.evaluate(frame(rightArmOnly, at: 0.7)).isReliable, "Either arm is enough from the side.")

        var empty = FramingEvaluator(requiredJoints: definition.requiredJoints, anyOfRequiredJoints: definition.anyOfRequiredJoints,
                                     headroomArmLengths: nil, cameraView: .side)
        let noArm: [LandmarkType: CGPoint] = [.nose: CGPoint(x: 560, y: 600), .rightShoulder: CGPoint(x: 540, y: 700),
                                              .rightHip: CGPoint(x: 540, y: 1100)]
        XCTAssertEqual(empty.evaluate(frame(noArm, at: 0)).guidance, .stepBackSideOn)
    }

    // MARK: - Helpers

    private func variant(top: ArmAngles) -> ArmMotion {
        ArmMotion(keyframes: [
            ArmKeyframe(angles: motion.startAngles, moveDuration: 0, holdDuration: 1.0, stepIndex: 0),
            ArmKeyframe(angles: top, moveDuration: 1.0, holdDuration: 0.4, stepIndex: 1),
            ArmKeyframe(angles: motion.startAngles, moveDuration: 1.5, holdDuration: 0, stepIndex: 2)
        ])
    }

    private func frame(_ points: [LandmarkType: CGPoint], at time: TimeInterval) -> PoseFrame {
        let landmarks = Dictionary(uniqueKeysWithValues: points.map { type, point in
            (type, Landmark(type: type, normalizedLocation: .zero, imageLocation: point, confidence: 0.9))
        })
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920), timestamp: time)
    }

    private struct Run {
        var reps = 0
        var forms: [RepForm] = []
        var signals: [Set<CoachingCueID>] = []
    }

    /// Samples `motion` at 10 Hz for three loops on the side-view demo figure. It can face either way,
    /// use the right arm instead of the left, change scale and proportions, and tip the upper arm.
    @MainActor
    private func run(_ motion: ArmMotion, scale: CGFloat = 1, upperArm: CGFloat = 1, forearm: CGFloat = 1,
                     mirrored: Bool = false, rightArm: Bool = false,
                     upperArmTilt: (TimeInterval) -> Double = { _ in 0 }) -> Run {
        let analyzer = TricepsExtensionAnalyzer(epoch: 1)
        var result = Run()
        for index in 0..<(Int(motion.duration * 10) * 3) {
            let time = Double(index) / 10
            var joints = ExerciseDemoFigureView.sideFigureJoints
            var angles = motion.sample(at: time).angles
            angles.upperArmElevation -= upperArmTilt(time)
            if let shoulder = joints[.leftShoulder] {
                let arm = ArmMotion.place(shoulder: shoulder, outward: 1, upperArm: ExerciseDemoFigureView.upperArm * upperArm,
                                          forearm: ExerciseDemoFigureView.forearm * forearm, angles: angles)
                joints[.leftElbow] = arm.elbow
                joints[.leftWrist] = arm.wrist
            }
            if rightArm {
                for side in [(LandmarkType.leftShoulder, LandmarkType.rightShoulder), (.leftElbow, .rightElbow),
                             (.leftWrist, .rightWrist), (.leftHip, .rightHip), (.leftKnee, .rightKnee), (.leftAnkle, .rightAnkle)] {
                    joints[side.1] = joints.removeValue(forKey: side.0)
                }
            }
            let landmarks = Dictionary(uniqueKeysWithValues: joints.map { type, point in
                let x = mirrored ? 300 - point.x : point.x
                return (type, Landmark(type: type, normalizedLocation: .zero,
                                       imageLocation: CGPoint(x: x * scale + 300, y: point.y * scale + 400), confidence: 0.9))
            })
            let analysis = analyzer.process(PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920),
                                                      timestamp: time), counting: true)
            result.reps += analysis.repEvents.count
            result.forms += analysis.repForms
            result.signals.append(analysis.formSignals)
        }
        return result
    }
}
