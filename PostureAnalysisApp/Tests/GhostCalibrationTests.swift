import XCTest
@testable import PostureAnalysisApp

/// When the setup ghost may fit the user, and the steadiness gate that decides when it does.
final class GhostCalibrationTests: XCTestCase {
    func testFloorGhostNeedsBothWristsAndMetrics() {
        let motion = ShoulderPressExercise.definition().guide.motion
        let metrics = GuideMetrics(upperArm: 100, forearm: 80)
        let wrists = overlay([.leftWrist: false, .rightWrist: false])
        let oneWrist = overlay([.leftWrist: false])

        XCTAssertTrue(GhostCalibration.canFit(overlay: wrists, metrics: metrics, motion: motion,
                                              cameraView: .floor, sample: motion.startSample))
        XCTAssertFalse(GhostCalibration.canFit(overlay: oneWrist, metrics: metrics, motion: motion,
                                               cameraView: .floor, sample: motion.startSample))
        XCTAssertFalse(GhostCalibration.canFit(overlay: wrists, metrics: nil, motion: motion,
                                               cameraView: .floor, sample: motion.startSample))
    }

    func testLegGhostUsesOneCompleteSideAndTheOtherAnkleWithoutMetrics() {
        let motion = legMotion()
        let partialOtherSide = overlay([
            .leftAnkle: false, .leftKnee: false,
            .rightAnkle: false, .rightKnee: false, .rightHip: false
        ])
        let missingOtherAnkle = overlay([
            .leftAnkle: false, .leftKnee: false, .leftHip: false,
            .rightKnee: false, .rightHip: false
        ])

        XCTAssertTrue(GhostCalibration.canFit(overlay: partialOtherSide, metrics: nil,
                                              motion: motion, cameraView: .front, sample: motion.startSample))
        XCTAssertFalse(GhostCalibration.canFit(overlay: missingOtherAnkle, metrics: nil,
                                               motion: motion, cameraView: .front, sample: motion.startSample))
    }

    func testFrontGhostNeedsBothNonStaleShouldersAndMetrics() {
        let motion = ShoulderPressExercise.definition().guide.motion
        let metrics = GuideMetrics(upperArm: 100, forearm: 80)
        let shoulders = overlay([.leftShoulder: false, .rightShoulder: false])
        let staleShoulder = overlay([.leftShoulder: false, .rightShoulder: true])

        XCTAssertTrue(GhostCalibration.canFit(overlay: shoulders, metrics: metrics, motion: motion,
                                              cameraView: .front, sample: motion.startSample))
        XCTAssertFalse(GhostCalibration.canFit(overlay: staleShoulder, metrics: metrics,
                                               motion: motion, cameraView: .front, sample: motion.startSample))
    }

    func testSideGhostNeedsOneNonStaleShoulderAndMetrics() {
        let motion = ShoulderPressExercise.definition().guide.motion
        let shoulder = overlay([.leftShoulder: false])
        let staleShoulder = overlay([.leftShoulder: true])
        let metrics = GuideMetrics(upperArm: 100, forearm: 80)

        XCTAssertTrue(GhostCalibration.canFit(overlay: shoulder, metrics: metrics, motion: motion,
                                              cameraView: .side, sample: motion.startSample))
        XCTAssertFalse(GhostCalibration.canFit(overlay: shoulder, metrics: nil, motion: motion,
                                               cameraView: .side, sample: motion.startSample))
        XCTAssertFalse(GhostCalibration.canFit(overlay: staleShoulder, metrics: metrics,
                                               motion: motion, cameraView: .side, sample: motion.startSample))
    }

    func testNilOverlayCannotFit() {
        XCTAssertFalse(GhostCalibration.canFit(overlay: nil, metrics: nil,
                                              motion: ShoulderPressExercise.definition().guide.motion,
                                              cameraView: .front,
                                              sample: ShoulderPressExercise.definition().guide.motion.startSample))
    }

    func testGateCalibratesAtTheContinuousAvailabilityBoundary() {
        var gate = GhostCalibrationGate()

        XCTAssertFalse(gate.update(available: true, at: 0))
        XCTAssertFalse(gate.update(available: true, at: 0.59))
        XCTAssertTrue(gate.update(available: true, at: 0.6))
    }

    func testGateRequiresAContinuousRunBeforeCalibration() {
        var gate = GhostCalibrationGate()

        XCTAssertFalse(gate.update(available: true, at: 0))
        XCTAssertFalse(gate.update(available: true, at: 0.59))
        XCTAssertFalse(gate.update(available: false, at: 0.6))
        XCTAssertFalse(gate.update(available: true, at: 0.7))
        XCTAssertFalse(gate.update(available: true, at: 1.29))
        XCTAssertTrue(gate.update(available: true, at: 1.3))
    }

    func testGateKeepsCalibrationForGraceThenRequiresFreshCalibration() {
        var gate = GhostCalibrationGate()

        XCTAssertFalse(gate.update(available: true, at: 0))
        XCTAssertTrue(gate.update(available: true, at: 0.6))
        XCTAssertTrue(gate.update(available: false, at: 1.59))
        XCTAssertFalse(gate.update(available: false, at: 1.6))

        XCTAssertFalse(gate.update(available: true, at: 1.61))
        XCTAssertFalse(gate.update(available: true, at: 2.20))
        XCTAssertFalse(gate.update(available: true, at: 2.21))
        XCTAssertTrue(gate.update(available: true, at: 2.22))
    }

    func testAvailableFrameRestartsTheReleaseGracePeriod() {
        var gate = GhostCalibrationGate()

        _ = gate.update(available: true, at: 0)
        XCTAssertTrue(gate.update(available: true, at: 0.6))
        XCTAssertTrue(gate.update(available: false, at: 0.8))
        XCTAssertTrue(gate.update(available: true, at: 1.0))
        XCTAssertTrue(gate.update(available: false, at: 1.99))
        XCTAssertFalse(gate.update(available: false, at: 2.0))
    }

    func testResetClearsCalibrationAndItsTimestamps() {
        var gate = GhostCalibrationGate()

        _ = gate.update(available: true, at: 0)
        XCTAssertTrue(gate.update(available: true, at: 0.6))
        gate.reset()

        XCTAssertFalse(gate.isCalibrated)
        XCTAssertFalse(gate.update(available: true, at: 1.0))
        XCTAssertFalse(gate.update(available: true, at: 1.59))
        XCTAssertTrue(gate.update(available: true, at: 1.6))
    }

    private func overlay(_ staleByJoint: [LandmarkType: Bool]) -> WorkoutOverlayState {
        let joints = staleByJoint.mapValues { OverlayJoint(location: .zero, isStale: $0) }
        let pose = BodyPose(landmarks: [:], imageWidth: 1080, imageHeight: 1920)
        return WorkoutOverlayState(imageSize: CGSize(width: 1080, height: 1920), joints: joints,
                                   segments: [], endPositionSides: [], pose: pose)
    }

    private func legMotion() -> ArmMotion {
        ArmMotion(keyframes: [ArmKeyframe(
            angles: ArmAngles(upperArmElevation: 0, forearmElevation: 90),
            moveDuration: 0,
            holdDuration: 1,
            stepIndex: 0,
            legs: LegPose(hipDrop: 0.2)
        )])
    }
}
