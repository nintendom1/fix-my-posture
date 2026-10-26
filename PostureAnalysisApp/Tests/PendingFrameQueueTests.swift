import XCTest
@testable import PostureAnalysisApp

/// Camera deliveries waiting for the main actor during a stall.
final class PendingFrameQueueTests: XCTestCase {
    func testAStallKeepsEveryFrameInOrder() {
        var queue = PendingFrameQueue<Int>()
        for frame in 1...8 { queue.appendFrame(frame) }

        XCTAssertEqual(queue.drain(), Array(1...8), "A 0.8 s stall at 10 Hz loses nothing.")
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.droppedCount, 0)
    }

    func testALongerStallDropsTheOldestFrames() {
        var queue = PendingFrameQueue<Int>(capacity: 15)
        for frame in 1...20 { queue.appendFrame(frame) }

        XCTAssertEqual(queue.drain(), Array(6...20))
        XCTAssertEqual(queue.droppedCount, 5)
    }

    func testStatusChangesKeepTheirPlaceAndAreNeverDropped() {
        var queue = PendingFrameQueue<String>(capacity: 3)
        queue.appendFrame("f1")
        queue.appendStatus("interrupted")
        queue.appendStatus("running")
        for frame in 2...5 { queue.appendFrame("f\(frame)") }

        XCTAssertEqual(queue.drain(), ["interrupted", "running", "f3", "f4", "f5"],
                       "Frames from after the interruption come after it, and only frames overflow.")
        XCTAssertEqual(queue.droppedCount, 2)
    }

    func testRemoveAllForgetsEverythingWaiting() {
        var queue = PendingFrameQueue<Int>(capacity: 2)
        queue.appendFrame(1)
        queue.appendStatus(0)
        queue.removeAll()
        queue.appendFrame(2)
        queue.appendFrame(3)

        XCTAssertEqual(queue.drain(), [2, 3], "Cleared frames no longer count toward capacity.")
    }

    func testTheDefaultHoldsAboutOneAndAHalfSecondsAtTheCameraRate() {
        XCTAssertEqual(Double(PendingFrameQueue<Int>.defaultCapacity) / Double(WorkoutCameraController.frameRate), 1.5)
    }
}
