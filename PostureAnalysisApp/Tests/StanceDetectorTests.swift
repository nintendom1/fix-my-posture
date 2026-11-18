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

    func testTurningStartsOnTheFrameThatReachesTheDebounceDespiteRounding() {
        XCTAssertLessThan(1.3 - 1.1, StanceDetector.Configuration.standard.turningAfter,
                          "In floating point, 1.3 - 1.1 falls just short of 0.2.")
        var detector = StanceDetector(seed: .facing)
        XCTAssertFalse(detector.update(torsoFrame(ratio: 0.5, at: 1.0)).turning)
        XCTAssertFalse(detector.update(torsoFrame(ratio: 0.4, at: 1.1)).turning)
        XCTAssertFalse(detector.update(torsoFrame(ratio: 0.4, at: 1.2)).turning)
        XCTAssertTrue(detector.update(torsoFrame(ratio: 0.4, at: 1.3)).turning, "0.2 s of unclear readings at 10 Hz.")
    }

    func testTurnEvidenceCountsFromTheFirstUnclearOrOppositeReading() {
        var detector = StanceDetector(seed: .facing)
        _ = detector.update(torsoFrame(ratio: 0.5, at: 0))
        XCTAssertFalse(detector.mayBeTurning, "The settled stance is no evidence of a turn.")

        _ = detector.update(torsoFrame(ratio: 0.4, at: 0.1))
        XCTAssertFalse(detector.observation.turning)
        XCTAssertTrue(detector.mayBeTurning, "An unclear reading suggests a turn before the debounce confirms it.")

        _ = detector.update(torsoFrame(ratio: 0.5, at: 0.15))
        XCTAssertFalse(detector.mayBeTurning, "Back at the settled stance, the evidence clears.")

        _ = detector.update(torsoFrame(ratio: 0.3, at: 0.2))
        XCTAssertTrue(detector.mayBeTurning, "The opposite stance suggests a turn too.")

        _ = detector.update(poseFrame([:], at: 0.25))
        XCTAssertFalse(detector.mayBeTurning, "Nobody in view is no evidence of a turn.")
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
            if time < 0.2 {
                XCTAssertFalse(observation.turning, "Turning starts only after 0.2 s of unclear readings.")
            } else if time < 3.2 {
                XCTAssertTrue(observation.turning, "Expected turning at \(time)s.")
            } else {
                XCTAssertFalse(observation.turning, "Turning must clear at its cap.")
                XCTAssertFalse(detector.mayBeTurning, "Past the cap, the same evidence no longer suggests a turn.")
            }
        }
    }

    func testEvidenceFlickeringAtTheFacingThresholdSharesOneTurnBudget() {
        // Ratios either side of 0.5 every 0.1 s: each unclear reading suggests a turn, and each facing reading clears
        // that evidence before the debounce, so turning never starts. The budget still runs from the first evidence.
        let configuration = StanceDetector.Configuration.standard
        let budgetEnd = Int(((configuration.turningAfter + configuration.turningCap) * 10).rounded())
        var detector = StanceDetector(seed: .facing)
        for index in 0...60 {
            let time = Double(index) / 10
            let unclear = index.isMultiple(of: 2)
            let observation = detector.update(torsoFrame(ratio: unclear ? 0.49 : 0.51, at: time))
            XCTAssertEqual(observation, StanceDetector.Observation(settled: .facing, turning: false))
            XCTAssertEqual(detector.mayBeTurning, unclear && index < budgetEnd, "At \(time)s.")
        }
    }

    func testASpentTurnRearmsOnlyOnceTheSettledStanceHoldsThreeTenths() {
        // Unclear readings with one facing reading in every four keep the turn going until its cap.
        var detector = StanceDetector(seed: .facing)
        for index in 0...60 {
            let observation = detector.update(torsoFrame(ratio: index % 4 == 3 ? 0.51 : 0.49, at: Double(index) / 10))
            XCTAssertEqual(observation.turning, index >= 2 && index < 32, "At \(Double(index) / 10)s.")
            XCTAssertEqual(detector.mayBeTurning, index < 32, "At \(Double(index) / 10)s.")
        }

        // The facing stance held for 0.2 s doesn't end the turn, so the next unclear reading is no evidence.
        for time in [6.1, 6.2, 6.3] { _ = detector.update(torsoFrame(ratio: 0.51, at: time)) }
        _ = detector.update(torsoFrame(ratio: 0.49, at: 6.4))
        XCTAssertFalse(detector.mayBeTurning, "A brief return to the stance must not re-arm the turn.")

        // Held for 0.3 s, it does: the next turn is bridged from its first unclear reading and confirmed as usual.
        for time in [6.5, 6.6, 6.7, 6.8] { _ = detector.update(torsoFrame(ratio: 0.51, at: time)) }
        _ = detector.update(torsoFrame(ratio: 0.49, at: 6.9))
        XCTAssertTrue(detector.mayBeTurning, "A settled stance re-arms the next turn.")
        _ = detector.update(torsoFrame(ratio: 0.49, at: 7.0))
        XCTAssertTrue(detector.update(torsoFrame(ratio: 0.49, at: 7.1)).turning)
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
