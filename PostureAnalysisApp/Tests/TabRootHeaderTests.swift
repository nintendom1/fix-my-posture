import XCTest
@testable import PostureAnalysisApp

final class TabRootHeaderTests: XCTestCase {
    func testCompactBarAppearsOnlyAfterLargeTitleScrollsPastTopEdge() {
        let titleFrame = CGRect(x: 20, y: 64, width: 100, height: 40)

        XCTAssertFalse(TabRootHeaderCollapse.shouldShowCompactBar(scrollOffset: 0, titleFrame: titleFrame))
        XCTAssertFalse(TabRootHeaderCollapse.shouldShowCompactBar(scrollOffset: 103, titleFrame: titleFrame))
        XCTAssertTrue(TabRootHeaderCollapse.shouldShowCompactBar(scrollOffset: 104, titleFrame: titleFrame))
        XCTAssertTrue(TabRootHeaderCollapse.shouldShowCompactBar(scrollOffset: 200, titleFrame: titleFrame))
    }
}
