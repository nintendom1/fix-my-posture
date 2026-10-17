import XCTest
import SwiftUI

final class DesignMetricsTests: XCTestCase {
    private let exemptions: [String: [String: String]] = [
        "train": [
            "statusBar": "The iOS status bar belongs to the snapshot window, outside TrainHomeScreen.",
            "train.hero.lastDone": "Phase 4.4 adds routine rotation and last-done history; this phase reserves its space.",
            "tabbar": "The native TabView owns the tab bar; TrainHomeScreen does not lay it out."
        ]
    ]

    @MainActor
    func testTrainFrame() throws {
        let result = try SnapshotHost.render(TrainHomeFixtures.designTabView, frameId: "train", testCase: self)
        XCTAssertEqual(result.hostSafeAreaInsets.top, 54, accuracy: 0.5)
        XCTAssertEqual(result.hostSafeAreaInsets.bottom, 34, accuracy: 0.5)
        XCTAssertEqual(result.hostFrameInWindow, CGRect(origin: .zero, size: DesignWindow.fixedSize))
        XCTAssertEqual(result.window.windowScene?.activationState, .foregroundActive)
        try assertAnchors(frameId: "train", actual: result.snapshotMeasuredAnchors)
    }

    @MainActor
    func testTrainSnapshotTitleFrameMatchesAnchorTestFrame() throws {
        let result = try SnapshotHost.render(
            TrainHomeFixtures.designTabView,
            frameId: "train-title-frame",
            markerAnchor: "train.title"
        )
        let anchorTestedFrame = try XCTUnwrap(result.anchors["train.title"])
        let snapshotMeasuredFrame = try XCTUnwrap(result.snapshotMeasuredAnchors["train.title"])
        let imageMeasuredFrame = try XCTUnwrap(result.magentaMarkerFrame)
        XCTAssertEqual(snapshotMeasuredFrame.minX, anchorTestedFrame.minX, accuracy: 0.01)
        XCTAssertEqual(snapshotMeasuredFrame.minY, anchorTestedFrame.minY, accuracy: 0.01)
        XCTAssertEqual(snapshotMeasuredFrame.width, anchorTestedFrame.width, accuracy: 0.01)
        XCTAssertEqual(snapshotMeasuredFrame.height, anchorTestedFrame.height, accuracy: 0.01)
        XCTAssertEqual(imageMeasuredFrame.minX, anchorTestedFrame.minX, accuracy: 0.5)
        XCTAssertEqual(imageMeasuredFrame.minY, anchorTestedFrame.minY, accuracy: 0.5)
        XCTAssertEqual(imageMeasuredFrame.width, 3, accuracy: 0.5)
        XCTAssertEqual(imageMeasuredFrame.height, 3, accuracy: 0.5)
    }

    @MainActor
    func testTrainQuickStartThumbHeightMatchesHTML() throws {
        let result = try SnapshotHost.render(TrainHomeFixtures.designTabView, frameId: "train-thumb-height")
        for index in 0..<4 {
            let frame = try XCTUnwrap(result.snapshotMeasuredAnchors["train.quickStart.tile\(index).thumb"])
            // HTML sets a 72 pt content height plus 8 pt top and bottom padding.
            XCTAssertEqual(frame.height, 88, accuracy: 0.5, "Quick Start thumbnail \(index)")
        }
    }

    func testCommittedMetricsContainStableAnchors() throws {
        let metrics = try DesignMetrics.load()
        XCTAssertEqual(metrics.version, 1)
        XCTAssertEqual(metrics.renderer, "playwright-webkit-2370")
        XCTAssertEqual(metrics.frames.count, 21)
        XCTAssertTrue(metrics.frames.values.allSatisfy { !$0.anchors.isEmpty })
    }

    func testToleranceRules() {
        XCTAssertEqual(DesignMetrics.tolerance(for: .box), 1)
        XCTAssertEqual(DesignMetrics.tolerance(for: .text), 2)
    }

    func testProbeAnchorsUseTheirDeclaredTolerance() {
        let expected = CGRect(x: 20, y: 120, width: 100, height: 50)
        let actual = CGRect(x: 20.5, y: 120.5, width: 100.5, height: 50.5)
        XCTAssertEqual(actual.minX, expected.minX, accuracy: DesignMetrics.tolerance(for: .box))
        XCTAssertEqual(actual.minY, expected.minY, accuracy: DesignMetrics.tolerance(for: .box))
        XCTAssertEqual(actual.width, expected.width, accuracy: DesignMetrics.tolerance(for: .box))
        XCTAssertEqual(actual.height, expected.height, accuracy: DesignMetrics.tolerance(for: .box))
    }

    func assertAnchors(
        frameId: String,
        actual: [String: CGRect],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let metrics = try DesignMetrics.load()
        guard let frame = metrics.frames[frameId] else {
            XCTFail("Unknown design frame: \(frameId)", file: file, line: line)
            return
        }
        for (name, expected) in frame.anchors where exemptions[frameId]?[name] == nil {
            guard let rect = actual[name] else {
                XCTFail("Missing anchor \(frameId).\(name)", file: file, line: line)
                continue
            }
            let tolerance = DesignMetrics.tolerance(for: expected.kind)
            XCTAssertEqual(rect.minX, CGFloat(expected.x), accuracy: tolerance, "\(frameId).\(name).x", file: file, line: line)
            XCTAssertEqual(rect.minY, CGFloat(expected.y), accuracy: tolerance, "\(frameId).\(name).y", file: file, line: line)
            XCTAssertEqual(rect.width, CGFloat(expected.width), accuracy: tolerance, "\(frameId).\(name).width", file: file, line: line)
            XCTAssertEqual(rect.height, CGFloat(expected.height), accuracy: tolerance, "\(frameId).\(name).height", file: file, line: line)
        }
    }
}
