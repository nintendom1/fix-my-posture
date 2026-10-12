import XCTest
@testable import PostureAnalysisApp

final class ShoulderPressAnalyzerTests: XCTestCase {
    private let motion = ShoulderPressExercise.definition().guide.motion

    @MainActor
    func testGuideDemonstrationCountsOneRepPerLoop() {
        XCTAssertEqual(run(motion).reps, 3)
    }

    @MainActor
    func testReadingsAreIdenticalAtAnyDistance() {
        let base = run(motion)
        for (scale, offset) in [(CGFloat(0.5), CGPoint(x: 400, y: 900)), (2, CGPoint(x: 100, y: 300))] {
            let scaled = run(motion, scale: scale, offset: offset)
            XCTAssertEqual(scaled.reps, 3)
            let largestDifference = zip(base.readings, scaled.readings).flatMap { a, b in
                BodySide.allCases.map { abs((a[$0]?.signal ?? 0) - (b[$0]?.signal ?? 0)) }
            }.max() ?? 0
            XCTAssertLessThan(largestDifference, 1e-9, "Heights are in arm lengths, so scale must not matter.")
            XCTAssertEqual(scaled.formReadings, base.formReadings)
        }
    }

    @MainActor
    func testCountsWithoutHipsInView() {
        XCTAssertEqual(run(motion, hips: false).reps, 3)
    }

    @MainActor
    func testHalfPressDoesNotCount() {
        XCTAssertEqual(run(halfPress).reps, 0)
    }

    @MainActor
    func testLockedTopThresholdHoldsWhileShouldersLift() {
        let lifted = run(motion, shoulderLift: 20)
        XCTAssertEqual(lifted.reps, 3)
        // Within the first rep, once the arm has left the start the locked line must not move.
        let lockedTops = (10..<40).filter { lifted.readings[$0][.left]?.zone != .bottom }
            .compactMap { lifted.thresholds[$0][.left] }
            .filter(\.isLocked)
            .map(\.topY)
        XCTAssertGreaterThan(lockedTops.count, 3)
        XCTAssertEqual((lockedTops.max() ?? 0) - (lockedTops.min() ?? 0), 0, accuracy: 0.001)
    }

    // MARK: - Form coaching

    @MainActor
    func testGuideDemonstrationRaisesNoCues() {
        let result = run(motion)
        XCTAssertEqual(result.forms.count, 3)
        XCTAssertTrue(result.forms.allSatisfy { $0.flags.isEmpty }, "\(result.forms)")
        XCTAssertTrue(result.signals.allSatisfy(\.isEmpty))
    }

    @MainActor
    func testHalfPressAsksToPressAllTheWayUp() {
        let result = run(halfPress)
        XCTAssertEqual(result.forms.count, 3, "Attempts that don't count are still judged.")
        XCTAssertTrue(result.forms.allSatisfy { $0.flags.contains(.pressFullExtension) })
    }

    @MainActor
    func testFastLoweringAsksForControl() {
        var keyframes = motion.keyframes
        keyframes[2].moveDuration = 0.5
        // A short hold at the end keeps the last return inside the sampled loops.
        keyframes[2].holdDuration = 0.5
        let result = run(ArmMotion(keyframes: keyframes))
        XCTAssertEqual(result.reps, 3)
        XCTAssertGreaterThanOrEqual(result.forms.count, 2)
        XCTAssertTrue(result.forms.allSatisfy { $0.flags == [.pressControlledLowering] }, "\(result.forms)")
    }

    @MainActor
    func testLateArmAsksForEvenPress() {
        let result = run(motion, rightDelay: 0.4)
        XCTAssertGreaterThanOrEqual(result.forms.count, 2)
        XCTAssertTrue(result.forms.allSatisfy { $0.flags.contains(.pressEvenArms) }, "\(result.forms)")
    }

    @MainActor
    func testPressingAgainFromMidwayAsksToLowerFurther() {
        let midway = ArmAngles(upperArmElevation: 20, forearmElevation: 90)
        let repress = ArmMotion(keyframes: [
            ArmKeyframe(angles: motion.startAngles, moveDuration: 0, holdDuration: 1.0, stepIndex: 0),
            ArmKeyframe(angles: motion.topAngles, moveDuration: 1.0, holdDuration: 0.5, stepIndex: 1),
            ArmKeyframe(angles: midway, moveDuration: 1.0, holdDuration: 0.3, stepIndex: 2),
            ArmKeyframe(angles: motion.topAngles, moveDuration: 1.0, holdDuration: 0.5, stepIndex: 1),
            ArmKeyframe(angles: motion.startAngles, moveDuration: 1.5, holdDuration: 0, stepIndex: 2)
        ])
        let result = run(repress)
        XCTAssertEqual(result.reps, 3, "Each loop still ends in one full rep.")
        XCTAssertEqual(result.forms.filter { $0.flags.contains(.pressReturnToStart) }.count, 3)
    }

    @MainActor
    func testLeaningSidewaysRaisesTorsoSignalOnlyWithHips() {
        // From 4.5 s the shoulders and arms shift 30 px (about 0.23 arm lengths) sideways over the hips.
        let lean: (TimeInterval) -> CGFloat = { $0 >= 4.5 ? 30 : 0 }
        let leaning = run(motion, torsoShift: lean)
        XCTAssertFalse(leaning.signals[..<45].contains { $0.contains(.pressTorsoCentered) })
        XCTAssertTrue(leaning.signals[45...].allSatisfy { $0.contains(.pressTorsoCentered) })
        XCTAssertEqual(leaning.reps, 3, "Leaning never affects counting.")

        let withoutHips = run(motion, hips: false, torsoShift: lean)
        XCTAssertFalse(withoutHips.signals.contains { $0.contains(.pressTorsoCentered) })
    }

    // MARK: - Helpers

    /// Elbows only reach about 120°, with wrists short of the Top threshold.
    private var halfPress: ArmMotion {
        let start = motion.startAngles
        return ArmMotion(keyframes: [
            ArmKeyframe(angles: start, moveDuration: 0, holdDuration: 1.0, stepIndex: 0),
            ArmKeyframe(angles: ArmAngles(upperArmElevation: 35, forearmElevation: 95), moveDuration: 1.0, holdDuration: 0.5, stepIndex: 1),
            ArmKeyframe(angles: start, moveDuration: 1.5, holdDuration: 0, stepIndex: 2)
        ])
    }

    private struct Run {
        var reps = 0
        var readings: [[BodySide: ArmReading]] = []
        var thresholds: [[BodySide: ArmThresholds]] = []
        var forms: [RepForm] = []
        var signals: [Set<CoachingCueID>] = []
        var formReadings: [FormReading] = []
    }

    /// Samples `motion` at 10 Hz for three loops on the guide's own demo figure. The right arm can lag
    /// behind, and the shoulders and arms can shift sideways over the hips.
    @MainActor
    private func run(_ motion: ArmMotion, rightDelay: TimeInterval = 0, scale: CGFloat = 1, offset: CGPoint = .zero,
                     hips: Bool = true, shoulderLift: CGFloat = 0,
                     torsoShift: (TimeInterval) -> CGFloat = { _ in 0 }) -> Run {
        let analyzer = ShoulderPressAnalyzer(epoch: 1)
        var result = Run()
        for index in 0..<(Int(motion.duration * 10) * 3) {
            let time = Double(index) / 10
            let angles = motion.sample(at: time).angles
            var joints = ExerciseDemoFigureView.pose(for: angles).jointLocations
            if rightDelay > 0, let shoulder = joints[.rightShoulder], let other = joints[.leftShoulder] {
                let arm = ArmMotion.place(shoulder: shoulder, otherShoulder: other, upperArm: ExerciseDemoFigureView.upperArm,
                                          forearm: ExerciseDemoFigureView.forearm, angles: motion.sample(at: time - rightDelay).angles)
                joints[.rightElbow] = arm.elbow
                joints[.rightWrist] = arm.wrist
            }
            let shift = torsoShift(time)
            for side in BodySide.allCases {
                for joint in side.armJoints { joints[joint]?.x += shift }
            }
            if !hips {
                joints[.leftHip] = nil
                joints[.rightHip] = nil
            }
            // Shoulders, and the arms attached to them, rise as the arms go overhead.
            let raise = shoulderLift * CGFloat(max(0, min(1, (angles.upperArmElevation - motion.startAngles.upperArmElevation) / 88)))
            for side in BodySide.allCases {
                for joint in side.armJoints { joints[joint]?.y -= raise }
            }
            let landmarks = Dictionary(uniqueKeysWithValues: joints.map { type, point in
                (type, Landmark(type: type, normalizedLocation: .zero,
                                imageLocation: CGPoint(x: point.x * scale + offset.x, y: point.y * scale + offset.y),
                                confidence: 0.9))
            })
            let frame = PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920), timestamp: time)
            let analysis = analyzer.process(frame, counting: true)
            result.reps += analysis.repEvents.count
            result.readings.append(analysis.readings)
            result.thresholds.append(analysis.thresholds)
            result.forms += analysis.repForms
            result.signals.append(analysis.formSignals)
            result.formReadings = analysis.formReadings
        }
        return result
    }
}
