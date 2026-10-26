import XCTest
@testable import PostureAnalysisApp

/// Estimating joints that leave the image through an edge during a set.
final class OffscreenJointEstimatorTests: XCTestCase {
    func testLimbsHangOffTheJointNearerTheBody() {
        XCTAssertEqual(OffscreenJointEstimator.parent(of: .leftWrist), .leftElbow)
        XCTAssertEqual(OffscreenJointEstimator.parent(of: .rightElbow), .rightShoulder)
        XCTAssertEqual(OffscreenJointEstimator.parent(of: .leftAnkle), .leftKnee)
        XCTAssertEqual(OffscreenJointEstimator.parent(of: .rightKnee), .rightHip)
        XCTAssertNil(OffscreenJointEstimator.parent(of: .leftShoulder))
        XCTAssertNil(OffscreenJointEstimator.parent(of: .nose))
    }

    func testWristRisingOutThroughTopFollowsElbow() throws {
        var estimator = estimator()
        _ = estimator.complete(frame([.leftElbow: CGPoint(x: 500, y: 350), .leftWrist: CGPoint(x: 500, y: 150)], at: 0))
        _ = estimator.complete(frame([.leftElbow: CGPoint(x: 500, y: 330), .leftWrist: CGPoint(x: 500, y: 130)], at: 0.1))

        let firstEstimate = estimator.complete(frame([.leftElbow: CGPoint(x: 510, y: 80)], at: 0.2))
        let wrist = try XCTUnwrap(firstEstimate.pose[.leftWrist])
        XCTAssertEqual(wrist.imageLocation, CGPoint(x: 510, y: -120))
        XCTAssertEqual(wrist.confidence, 0.9)
        XCTAssertFalse(wrist.isManuallyCorrected)
        XCTAssertTrue(firstEstimate.estimatedJoints.contains(.leftWrist))
        XCTAssertEqual(wrist.normalizedLocation.x, wrist.imageLocation.x / 1080, accuracy: 1e-9)
        XCTAssertEqual(wrist.normalizedLocation.y, 1.0625, accuracy: 1e-9)

        let secondEstimate = estimator.complete(frame([.leftElbow: CGPoint(x: 520, y: 60)], at: 0.3))
        XCTAssertEqual(secondEstimate.pose[.leftWrist]?.imageLocation, CGPoint(x: 520, y: -140))
        XCTAssertTrue(secondEstimate.estimatedJoints.contains(.leftWrist))
    }

    func testRigidWristInsideFrameRotatesIntoTheNearestEdgeBand() throws {
        var estimator = estimator()
        _ = estimator.complete(frame([.leftElbow: CGPoint(x: 100, y: 270), .leftWrist: CGPoint(x: 260, y: 120)], at: 0))
        _ = estimator.complete(frame([.leftElbow: CGPoint(x: 100, y: 250), .leftWrist: CGPoint(x: 260, y: 100)], at: 0.1))

        let completed = estimator.complete(frame([.leftElbow: CGPoint(x: 100, y: 340)], at: 0.2))
        let wrist = try XCTUnwrap(completed.pose[.leftWrist])
        let vectorX = wrist.imageLocation.x - 100
        let vectorY = wrist.imageLocation.y - 340
        let length = hypot(vectorX, vectorY)
        let turn = abs(atan2(vectorY, vectorX) - atan2(-150.0, 160.0)) * 180 / .pi

        XCTAssertLessThanOrEqual(wrist.imageLocation.y, 0.08 * 1920)
        XCTAssertEqual(length, hypot(160, 150), accuracy: 0.001)
        XCTAssertEqual(turn, 15, accuracy: 1)
        XCTAssertTrue(completed.estimatedJoints.contains(.leftWrist))
    }

    func testNeededRotationOverThirtyFiveDegreesDoesNotEstimate() {
        var estimator = estimator()
        _ = estimator.complete(frame([.leftElbow: CGPoint(x: 100, y: 220), .leftWrist: CGPoint(x: 272, y: 130)], at: 0))
        _ = estimator.complete(frame([.leftElbow: CGPoint(x: 100, y: 210), .leftWrist: CGPoint(x: 272, y: 120)], at: 0.1))

        let completed = estimator.complete(frame([.leftElbow: CGPoint(x: 100, y: 330)], at: 0.2))
        XCTAssertNil(completed.pose[.leftWrist])
        XCTAssertFalse(completed.estimatedJoints.contains(.leftWrist))
    }

    func testMidImageOcclusionDoesNotEstimate() {
        var estimator = estimator()
        _ = estimator.complete(frame([.leftElbow: CGPoint(x: 500, y: 1200), .leftWrist: CGPoint(x: 520, y: 900)], at: 0))
        _ = estimator.complete(frame([.leftElbow: CGPoint(x: 500, y: 1190), .leftWrist: CGPoint(x: 520, y: 890)], at: 0.1))

        // The rigid point would be at the top edge, but the wrist disappeared in the middle of the image.
        let completed = estimator.complete(frame([.leftElbow: CGPoint(x: 500, y: 200)], at: 0.2))
        XCTAssertNil(completed.pose[.leftWrist])
    }

    func testJointMovingAwayFromTopDoesNotEstimate() {
        var estimator = estimator()
        _ = estimator.complete(frame([.leftElbow: CGPoint(x: 500, y: 300), .leftWrist: CGPoint(x: 500, y: 100)], at: 0))
        _ = estimator.complete(frame([.leftElbow: CGPoint(x: 500, y: 310), .leftWrist: CGPoint(x: 500, y: 130)], at: 0.1))

        let completed = estimator.complete(frame([.leftElbow: CGPoint(x: 500, y: 320)], at: 0.2))
        XCTAssertNil(completed.pose[.leftWrist])
    }

    func testMissingParentDoesNotEstimate() {
        var estimator = estimator()
        _ = estimator.complete(frame([.leftElbow: CGPoint(x: 500, y: 300), .leftWrist: CGPoint(x: 500, y: 100)], at: 0))
        _ = estimator.complete(frame([.leftElbow: CGPoint(x: 500, y: 310), .leftWrist: CGPoint(x: 500, y: 90)], at: 0.1))

        let completed = estimator.complete(frame([:], at: 0.2))
        XCTAssertNil(completed.pose[.leftWrist])
    }

    func testEstimateExpiresAfterMaximumDuration() {
        var estimator = estimator()
        _ = estimator.complete(frame([.leftElbow: CGPoint(x: 500, y: 300), .leftWrist: CGPoint(x: 500, y: 100)], at: 0))
        _ = estimator.complete(frame([.leftElbow: CGPoint(x: 500, y: 290), .leftWrist: CGPoint(x: 500, y: 90)], at: 0.1))

        let atLimit = estimator.complete(frame([.leftElbow: CGPoint(x: 500, y: 280)], at: 1.6))
        XCTAssertNotNil(atLimit.pose[.leftWrist], "1.5 s after the last observation is still within the limit.")
        XCTAssertTrue(atLimit.estimatedJoints.contains(.leftWrist))

        let afterLimit = estimator.complete(frame([.leftElbow: CGPoint(x: 500, y: 270)], at: 1.7))
        XCTAssertNil(afterLimit.pose[.leftWrist], "1.6 s after the last observation is too old.")
    }

    func testReappearingWristUsesObservationWithoutEstimateFlag() throws {
        var estimator = estimator()
        _ = estimator.complete(frame([.leftElbow: CGPoint(x: 500, y: 300), .leftWrist: CGPoint(x: 500, y: 100)], at: 0))
        _ = estimator.complete(frame([.leftElbow: CGPoint(x: 500, y: 290), .leftWrist: CGPoint(x: 500, y: 90)], at: 0.1))
        _ = estimator.complete(frame([.leftElbow: CGPoint(x: 500, y: 280)], at: 0.2))

        let observed = frame([.leftElbow: CGPoint(x: 500, y: 270), .leftWrist: CGPoint(x: 540, y: 110)], at: 0.3)
        let completed = estimator.complete(observed)
        XCTAssertEqual(completed.pose[.leftWrist]?.imageLocation, CGPoint(x: 540, y: 110))
        XCTAssertFalse(completed.estimatedJoints.contains(.leftWrist))
    }

    func testPlantedWristStaysPutUntilParentMovesBeyondReach() throws {
        var estimator = estimator(planted: [.leftWrist])
        _ = estimator.complete(frame([.leftElbow: CGPoint(x: 500, y: 1600), .leftWrist: CGPoint(x: 500, y: 1840)], at: 0))
        _ = estimator.complete(frame([.leftElbow: CGPoint(x: 510, y: 1610), .leftWrist: CGPoint(x: 510, y: 1850)], at: 0.1))

        let held = estimator.complete(frame([.leftElbow: CGPoint(x: 520, y: 1640)], at: 0.2))
        let wrist = try XCTUnwrap(held.pose[.leftWrist])
        XCTAssertEqual(wrist.imageLocation, CGPoint(x: 510, y: 1850))
        XCTAssertTrue(held.estimatedJoints.contains(.leftWrist))

        let outOfReach = estimator.complete(frame([.leftElbow: CGPoint(x: 520, y: 1540)], at: 0.3))
        XCTAssertNil(outOfReach.pose[.leftWrist])
        XCTAssertFalse(outOfReach.estimatedJoints.contains(.leftWrist))
    }

    func testOnlyConfiguredJointsWithAParentCanBeEstimated() {
        var outside = estimator(joints: [])
        _ = outside.complete(frame([.leftElbow: CGPoint(x: 500, y: 300), .leftWrist: CGPoint(x: 500, y: 100)], at: 0))
        _ = outside.complete(frame([.leftElbow: CGPoint(x: 500, y: 290), .leftWrist: CGPoint(x: 500, y: 90)], at: 0.1))
        XCTAssertNil(outside.complete(frame([.leftElbow: CGPoint(x: 500, y: 280)], at: 0.2)).pose[.leftWrist])

        var noParent = estimator(joints: [.leftShoulder])
        _ = noParent.complete(frame([.leftShoulder: CGPoint(x: 500, y: 100)], at: 0))
        XCTAssertNil(noParent.complete(frame([:], at: 0.1)).pose[.leftShoulder])
    }

    func testResetClearsObservationHistory() {
        var estimator = estimator()
        _ = estimator.complete(frame([.leftElbow: CGPoint(x: 500, y: 300), .leftWrist: CGPoint(x: 500, y: 100)], at: 0))
        _ = estimator.complete(frame([.leftElbow: CGPoint(x: 500, y: 290), .leftWrist: CGPoint(x: 500, y: 90)], at: 0.1))
        estimator.reset()

        XCTAssertNil(estimator.complete(frame([.leftElbow: CGPoint(x: 500, y: 280)], at: 0.2)).pose[.leftWrist])
    }

    func testCompletedFramesKeepTheirSequenceAndLowConfidenceJoints() throws {
        var estimator = estimator()
        _ = estimator.complete(frame([.leftElbow: CGPoint(x: 500, y: 350), .leftWrist: CGPoint(x: 500, y: 150)], at: 0))
        _ = estimator.complete(frame([.leftElbow: CGPoint(x: 500, y: 330), .leftWrist: CGPoint(x: 500, y: 130)], at: 0.1))
        var input = frame([.leftElbow: CGPoint(x: 510, y: 80)], at: 0.2)
        input.sequence = 12
        let faint = Landmark(type: .leftWrist, normalizedLocation: CGPoint(x: 0.5, y: 1), imageLocation: CGPoint(x: 540, y: 2),
                             confidence: 0.12)
        input.lowConfidenceLandmarks = [.leftWrist: faint]

        let completed = estimator.complete(input)

        XCTAssertTrue(completed.estimatedJoints.contains(.leftWrist))
        XCTAssertEqual(completed.sequence, 12)
        XCTAssertEqual(completed.lowConfidenceLandmarks, [.leftWrist: faint])
    }

    private func estimator(joints: Set<LandmarkType> = [.leftWrist], planted: Set<LandmarkType> = []) -> OffscreenJointEstimator {
        OffscreenJointEstimator(joints: joints, plantedJoints: planted)
    }

    private func frame(_ points: [LandmarkType: CGPoint], at time: TimeInterval) -> PoseFrame {
        let landmarks = Dictionary(uniqueKeysWithValues: points.map { type, point in
            (type, Landmark(type: type,
                            normalizedLocation: CGPoint(x: point.x / 1080, y: 1 - point.y / 1920),
                            imageLocation: point,
                            confidence: 0.9))
        })
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1080, imageHeight: 1920), timestamp: time)
    }
}
