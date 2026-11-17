import XCTest
@testable import PostureAnalysisApp

final class StanceDetectorTests: XCTestCase {
    func testShoulderWidthAndTorsoRatioClassifyFacingSideOnAndUnclear() {
        XCTAssertEqual(StanceDetector.reading(of: torsoFrame(ratio: 0.5, at: 0), configuration: .standard), .facing)
        XCTAssertEqual(StanceDetector.reading(of: torsoFrame(ratio: 0.3, at: 0), configuration: .standard), .sideOn)
        XCTAssertEqual(StanceDetector.reading(of: torsoFrame(ratio: 0.4, at: 0), configuration: .standard), .unclear)
    }

    func testShouldersWithoutHipsUseTheLongestUpperArm() {
        XCTAssertEqual(StanceDetector.reading(of: armFrame(ratio: 0.75, at: 0), configuration: .standard), .facing)
        XCTAssertEqual(StanceDetector.reading(of: armFrame(ratio: 0.4, at: 0), configuration: .standard), .sideOn)
        XCTAssertEqual(StanceDetector.reading(of: armFrame(ratio: 0.55, at: 0), configuration: .standard), .unclear)
    }

    func testOneAttachedShoulderReadsSideOnOnlyInsideTheFrameMargin() {
        let inside = poseFrame([.leftShoulder: CGPoint(x: 100, y: 500),
                                .leftElbow: CGPoint(x: 110, y: 620)], at: 0)
        let atEdge = poseFrame([.leftShoulder: CGPoint(x: 99, y: 500),
                                .leftElbow: CGPoint(x: 110, y: 620)], at: 0)

        XCTAssertEqual(StanceDetector.reading(of: inside, configuration: .standard), .sideOn)
        XCTAssertEqual(StanceDetector.reading(of: atEdge, configuration: .standard), .unclear)
    }

    func testNoConfidentBodyIsAbsentAndConfidenceFloorIsInclusive() {
        let empty = poseFrame([:], at: 0)
        let atFloor = torsoFrame(ratio: 0.5, at: 0, confidence: 0.3)
        let belowFloor = torsoFrame(ratio: 0.5, at: 0, confidence: 0.29)

        XCTAssertEqual(StanceDetector.reading(of: empty, configuration: .standard), .absent)
        XCTAssertEqual(StanceDetector.reading(of: atFloor, configuration: .standard), .facing)
        XCTAssertEqual(StanceDetector.reading(of: belowFloor, configuration: .standard), .absent)
    }

    func testOppositeStanceMustHoldForOneSecondInEitherDirection() {
        var detector = StanceDetector(seed: .facing)
        for time in [0.0, 0.25, 0.5, 0.75, 0.99] {
            XCTAssertEqual(detector.update(torsoFrame(ratio: 0.3, at: time)).settled, .facing)
        }
        XCTAssertEqual(detector.update(torsoFrame(ratio: 0.3, at: 1.0)).settled, .sideOn)

        for time in [1.1, 1.35, 1.6, 1.85, 2.099] {
            XCTAssertEqual(detector.update(torsoFrame(ratio: 0.5, at: time)).settled, .sideOn)
        }
        XCTAssertEqual(detector.update(torsoFrame(ratio: 0.5, at: 2.101)).settled, .facing)
    }

    func testThreeQuarterFlappingNeverChangesTheSettledStance() {
        var detector = StanceDetector(seed: .facing)
        for index in 0...15 {
            let time = Double(index) * 0.35
            let ratio: Double
            switch index % 3 {
            case 0: ratio = 0.28
            case 1: ratio = 0.4
            default: ratio = 0.55
            }
            XCTAssertEqual(detector.update(torsoFrame(ratio: ratio, at: time)).settled, .facing)
        }
    }

    func testTurningStartsAfterTwoTenthsAndClearsAfterThreeTenthsBackAtStance() {
        var detector = StanceDetector(seed: .facing)
        XCTAssertFalse(detector.update(torsoFrame(ratio: 0.4, at: 0)).turning)
        XCTAssertFalse(detector.update(torsoFrame(ratio: 0.4, at: 0.19)).turning)
        XCTAssertTrue(detector.update(torsoFrame(ratio: 0.4, at: 0.2)).turning)

        XCTAssertTrue(detector.update(torsoFrame(ratio: 0.5, at: 0.21)).turning)
        XCTAssertTrue(detector.update(torsoFrame(ratio: 0.5, at: 0.5)).turning)
        XCTAssertFalse(detector.update(torsoFrame(ratio: 0.5, at: 0.511)).turning)
    }

    func testTurningClearsAfterThreeTenthsWithoutAVisibleBody() {
        var detector = StanceDetector(seed: .facing)
        _ = detector.update(torsoFrame(ratio: 0.4, at: 0))
        XCTAssertTrue(detector.update(torsoFrame(ratio: 0.4, at: 0.2)).turning)

        XCTAssertTrue(detector.update(poseFrame([:], at: 0.21)).turning)
        XCTAssertTrue(detector.update(poseFrame([:], at: 0.5)).turning)
        XCTAssertFalse(detector.update(poseFrame([:], at: 0.511)).turning)
    }

    func testTurningHasAThreeSecondCapEvenWhileTheReadingStaysUnclear() {
        var detector = StanceDetector(seed: .facing)
        for index in 0...32 {
            let time = Double(index) / 10
            let observation = detector.update(torsoFrame(ratio: 0.4, at: time))
            if time < 3.2 {
                XCTAssertTrue(observation.turning, "Expected turning at \(time)s.")
            } else {
                XCTAssertFalse(observation.turning, "Turning must clear at its cap.")
            }
        }
    }

    func testResetClearsTheCandidateAndTurningState() {
        var detector = StanceDetector(seed: .facing)
        _ = detector.update(torsoFrame(ratio: 0.4, at: 0))
        _ = detector.update(torsoFrame(ratio: 0.4, at: 0.2))
        XCTAssertTrue(detector.observation.turning)

        detector.reset(seed: .sideOn)

        XCTAssertEqual(detector.observation, StanceDetector.Observation(settled: .sideOn, turning: false))
        XCTAssertEqual(detector.update(torsoFrame(ratio: 0.5, at: 1)).settled, .sideOn)
    }

    private func torsoFrame(ratio: Double, at time: TimeInterval, confidence: Double = 0.9) -> PoseFrame {
        let width = CGFloat(ratio * 400)
        let points: [LandmarkType: CGPoint] = [
            .leftShoulder: CGPoint(x: 500 - width / 2, y: 300),
            .rightShoulder: CGPoint(x: 500 + width / 2, y: 300),
            .leftHip: CGPoint(x: 480, y: 700),
            .rightHip: CGPoint(x: 520, y: 700)
        ]
        return poseFrame(points, at: time, confidence: confidence)
    }

    private func armFrame(ratio: Double, at time: TimeInterval) -> PoseFrame {
        let width = CGFloat(ratio * 200)
        let leftShoulder = CGPoint(x: 500 - width / 2, y: 300)
        let rightShoulder = CGPoint(x: 500 + width / 2, y: 300)
        return poseFrame([.leftShoulder: leftShoulder,
                          .rightShoulder: rightShoulder,
                          .leftElbow: CGPoint(x: leftShoulder.x, y: 400),
                          .rightElbow: CGPoint(x: rightShoulder.x, y: 500)], at: time)
    }

    private func poseFrame(_ points: [LandmarkType: CGPoint], at time: TimeInterval,
                           confidence: Double = 0.9) -> PoseFrame {
        let landmarks = Dictionary(uniqueKeysWithValues: points.map { type, point in
            (type, Landmark(type: type, normalizedLocation: .zero, imageLocation: point, confidence: confidence))
        })
        return PoseFrame(pose: BodyPose(landmarks: landmarks, imageWidth: 1000, imageHeight: 1000), timestamp: time)
    }
}
