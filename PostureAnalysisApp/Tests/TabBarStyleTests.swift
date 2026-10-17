import XCTest
@testable import PostureAnalysisApp

final class TabBarStyleTests: XCTestCase {
    func testStyleMatchesTabBarDesignTokens() {
        let style = TabBarStyle.design

        XCTAssertEqual(style.background.red, 18.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(style.background.green, 14.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(style.background.blue, 28.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(style.background.alpha, 0.84, accuracy: 0.0001)
        XCTAssertEqual(style.inactiveColor.hex, 0x7D758C)
        XCTAssertEqual(style.hairlineColor.hex, 0xFFFFFF)
        XCTAssertEqual(style.hairlineColor.alpha, 0.06, accuracy: 0.0001)
        XCTAssertEqual(style.titleFont.pointSize, 11, accuracy: 0.0001)
        XCTAssertEqual(style.titleFont.weight, .heavy)
        XCTAssertTrue(style.titleFont.rounded)
    }

    func testTintUsesPostureBlueAndVioletForOtherTabs() {
        for tab in AppTab.allCases {
            XCTAssertEqual(TabBarStyle.design.tintHex(for: tab), tab == .posture ? 0x9FB0FF : 0xC9B3FF)
        }
    }
}
