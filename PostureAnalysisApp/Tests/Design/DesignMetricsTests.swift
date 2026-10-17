import XCTest

final class DesignMetricsTests: XCTestCase {
    private let exemptions: [String: Set<String>] = [:]

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
        for (name, expected) in frame.anchors where !exemptions[frameId, default: []].contains(name) {
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
