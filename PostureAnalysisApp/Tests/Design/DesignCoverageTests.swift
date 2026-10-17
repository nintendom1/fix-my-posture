import XCTest

final class DesignCoverageTests: XCTestCase {
    func testEveryFrameHasAFixtureOrIsPending() throws {
        let metrics = try DesignMetrics.load()
        let frameIDs = Set(metrics.frames.keys)
        XCTAssertEqual(frameIDs, ImplementedDesignFixtures.ids.union(PendingFrames.ids))
        XCTAssertTrue(PendingFrames.ids.isSubset(of: frameIDs), "PendingFrames contains an unknown frame id.")
        XCTAssertLessThanOrEqual(PendingFrames.ids.count, 21)
    }
}
