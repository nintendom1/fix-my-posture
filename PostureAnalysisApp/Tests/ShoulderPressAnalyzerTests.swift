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
        }
    }

    @MainActor
    func testCountsWithoutHipsInView() {
        XCTAssertEqual(run(motion, hips: false).reps, 3)
    }

    @MainActor
    func testHalfPressDoesNotCount() {
        let start = motion.startAngles
        // Elbows only reach about 120°, with wrists short of the Top threshold.
        let halfPress = ArmMotion(keyframes: [
            ArmKeyframe(angles: start, moveDuration: 0, holdDuration: 1.0, stepIndex: 0),
            ArmKeyframe(angles: ArmAngles(upperArmElevation: 35, forearmElevation: 95), moveDuration: 1.0, holdDuration: 0.5, stepIndex: 1),
            ArmKeyframe(angles: start, moveDuration: 1.5, holdDuration: 0, stepIndex: 2)
        ])
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

    private struct Run {
        var reps = 0
        var readings: [[BodySide: ArmReading]] = []
        var thresholds: [[BodySide: ArmThresholds]] = []
    }

    /// Samples `motion` at 10 Hz for three loops on the guide's own demo figure.
    @MainActor
    private func run(_ motion: ArmMotion, scale: CGFloat = 1, offset: CGPoint = .zero,
                     hips: Bool = true, shoulderLift: CGFloat = 0) -> Run {
        let analyzer = ShoulderPressAnalyzer(epoch: 1)
        var result = Run()
        for index in 0..<(Int(motion.duration * 10) * 3) {
            let time = Double(index) / 10
            let angles = motion.sample(at: time).angles
            var joints = ExerciseDemoFigureView.pose(for: angles).jointLocations
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
        }
        return result
    }
}
