import XCTest
import SwiftUI
import UIKit
@testable import PostureAnalysisApp

final class DesignHarnessTests: XCTestCase {
    @MainActor
    func testDesignWindowInsetsAreFixed() {
        let window = DesignWindow()
        XCTAssertEqual(window.safeAreaInsets.top, 54)
        XCTAssertEqual(window.safeAreaInsets.bottom, 34)
    }

    @MainActor
    func testRenderedImageIs1170x2532() throws {
        let result = try SnapshotHost.render(Color.black, frameId: "probe", testCase: self)
        XCTAssertEqual(result.image.size.width * result.image.scale, 1170)
        XCTAssertEqual(result.image.size.height * result.image.scale, 2532)
    }

    @MainActor
    func testAnchorFramesCrossTabAndNavigationHosting() throws {
        let host = TabView {
            NavigationStack { GeometryProbe() }
                .toolbar(.hidden, for: .navigationBar)
                .tabItem { Label("Probe", systemImage: "square") }
        }
        let result = try SnapshotHost.render(host, frameId: "probe", testCase: self)
        let frame = try XCTUnwrap(result.anchors["probe.box"])
        XCTAssertEqual(frame.minX, 20, accuracy: 0.5)
        XCTAssertEqual(frame.minY, 120, accuracy: 0.5)
        XCTAssertEqual(frame.width, 100, accuracy: 0.5)
        XCTAssertEqual(frame.height, 50, accuracy: 0.5)
    }

    @MainActor
    func testMetricsJSONDecodesAndHasAllFrames() throws {
        let metrics = try DesignMetrics.load()
        XCTAssertEqual(metrics.version, 1)
        XCTAssertEqual(metrics.frames.count, 21)
        XCTAssertEqual(metrics.viewport.width, 390)
        XCTAssertEqual(metrics.viewport.height, 844)
    }

    func testToleranceRules() {
        XCTAssertEqual(DesignMetrics.tolerance(for: .box), 1)
        XCTAssertEqual(DesignMetrics.tolerance(for: .text), 2)
    }

}

private struct GeometryProbe: View {
    var body: some View {
        GeometryReader { _ in
            Color.clear
                .frame(width: 100, height: 50)
                .designAnchor("probe.box")
                .position(x: 70, y: 145)
        }
        .ignoresSafeArea()
    }
}

