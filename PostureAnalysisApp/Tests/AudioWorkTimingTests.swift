import XCTest
@testable import PostureAnalysisApp

/// Timing audio work around coach speech, including its execution context.
final class AudioWorkTimingTests: XCTestCase {
    func testMeasureReportsTheStepAndItsDurationAndReturnsTheResult() {
        let timing = AudioWorkTiming()
        var measured: [(AudioWorkStep, TimeInterval, AudioWorkExecutionContext)] = []
        timing.onMeasured = { measured.append(($0, $1, $2)) }
        let expectedContext: AudioWorkExecutionContext = Thread.isMainThread ? .main : .worker

        let result = timing.measure(.activateForListening) { () -> Bool in
            Thread.sleep(forTimeInterval: 0.02)
            return true
        }

        XCTAssertTrue(result)
        XCTAssertEqual(measured.map(\.0), [.activateForListening])
        XCTAssertGreaterThanOrEqual(measured.first?.1 ?? 0, 0.02)
        XCTAssertEqual(measured.first?.2, expectedContext)
    }

    func testAThrowingStepIsStillReported() {
        struct Failure: Error {}
        let timing = AudioWorkTiming()
        var steps: [AudioWorkStep] = []
        let expectedContext: AudioWorkExecutionContext = Thread.isMainThread ? .main : .worker
        timing.onMeasured = { step, _, context in
            XCTAssertEqual(context, expectedContext)
            steps.append(step)
        }

        XCTAssertThrowsError(try timing.measure(.engineStart) { throw Failure() })
        XCTAssertEqual(steps, [.engineStart])
    }
}
