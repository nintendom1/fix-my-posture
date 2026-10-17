import XCTest
import SwiftUI
@testable import PostureAnalysisApp

@MainActor
final class AppShellSmokeTests: XCTestCase {
    func testEveryTabRootRendersInSnapshotHost() throws {
        let environment = AppEnvironment(inMemory: true)

        for tab in AppTab.allCases {
            environment.router.select(tab)
            XCTAssertNoThrow(try SnapshotHost.render(AppShellView(environment: environment),
                                                     frameId: "app-shell-\(tab.rawValue)", testCase: self),
                            "The \(tab.rawValue) root should render")
        }
    }
}
