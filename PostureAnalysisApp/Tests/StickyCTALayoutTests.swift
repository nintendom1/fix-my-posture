import XCTest
import SwiftUI
import UIKit
@testable import PostureAnalysisApp

@MainActor
final class StickyCTALayoutTests: XCTestCase {
    func testStickyCTAUsesDesignHeightMarginsAndTabBarGap() throws {
        let result = try SnapshotHost.render(StickyCTALayoutFixture(), frameId: "sticky-cta", testCase: self)
        let cta = try XCTUnwrap(result.anchors["sticky.cta"])
        let tabBar = try XCTUnwrap(findTabBar(in: result.window))
        let tabBarFrame = tabBar.convert(tabBar.bounds, to: result.window)

        XCTAssertEqual(cta.height, 58, accuracy: 0.5)
        XCTAssertEqual(cta.minX, 16, accuracy: 0.5)
        XCTAssertEqual(cta.width, 390 - 32, accuracy: 0.5)
        XCTAssertEqual(tabBarFrame.minY - cta.maxY, 12, accuracy: 0.5)
    }

    private func findTabBar(in view: UIView) -> UITabBar? {
        if let tabBar = view as? UITabBar { return tabBar }
        for child in view.subviews {
            if let tabBar = findTabBar(in: child) { return tabBar }
        }
        return nil
    }
}
