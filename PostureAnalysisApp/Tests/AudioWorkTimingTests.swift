import XCTest
@testable import PostureAnalysisApp

/// Timing the audio work that blocks the main thread around coach speech.
final class AudioWorkTimingTests: XCTestCase {
    func testMeasureReportsTheStepAndItsDurationAndReturnsTheResult() {
        let timing = AudioWorkTiming()
        var measured: [(AudioWorkStep, TimeInterval)] = []
        timing.onMeasured = { measured.append(($0, $1)) }

        let result = timing.measure(.activateForListening) { () -> Bool in
            Thread.sleep(forTimeInterval: 0.02)
            return true
        }

        XCTAssertTrue(result)
        XCTAssertEqual(measured.map(\.0), [.activateForListening])
        XCTAssertGreaterThanOrEqual(measured.first?.1 ?? 0, 0.02)
    }

    func testAThrowingStepIsStillReported() {
        struct Failure: Error {}
        let timing = AudioWorkTiming()
        var steps: [AudioWorkStep] = []
        timing.onMeasured = { step, _ in steps.append(step) }

        XCTAssertThrowsError(try timing.measure(.engineStart) { throw Failure() })
        XCTAssertEqual(steps, [.engineStart])
    }
}
