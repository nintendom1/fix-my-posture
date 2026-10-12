import XCTest
@testable import PostureAnalysisApp

final class PhoneTiltDetectorTests: XCTestCase {
    func testTiltMustPersistBeforeWarning() {
        var detector = PhoneTiltDetector()
        XCTAssertFalse(detector.update(pitchDegrees: 20, at: 0))
        XCTAssertFalse(detector.update(pitchDegrees: 20, at: 0.5))
        XCTAssertTrue(detector.update(pitchDegrees: 20, at: 1))

        var bumped = PhoneTiltDetector()
        _ = bumped.update(pitchDegrees: 20, at: 0)
        _ = bumped.update(pitchDegrees: 5, at: 0.5)
        XCTAssertFalse(bumped.update(pitchDegrees: 20, at: 1), "Returning upright restarts the wait.")
    }

    func testHysteresisAndMissingMotion() {
        var detector = PhoneTiltDetector()
        _ = detector.update(pitchDegrees: -18, at: 0)
        XCTAssertTrue(detector.update(pitchDegrees: -18, at: 1), "Leaning forward counts too.")
        XCTAssertTrue(detector.update(pitchDegrees: 12, at: 2), "Stays tilted until below the upright limit.")
        XCTAssertFalse(detector.update(pitchDegrees: 9, at: 3))
        XCTAssertFalse(detector.update(pitchDegrees: 12, at: 4), "Re-entering needs the higher limit.")
        XCTAssertFalse(detector.update(pitchDegrees: nil, at: 5), "No motion data never warns.")
    }
}
