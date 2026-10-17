import XCTest
import SwiftUI
import UIKit
@testable import PostureAnalysisApp

final class WorkoutJointOverlayColorTests: XCTestCase {
    func testTrackedLinesFollowTheVisualStateColorRole() {
        let ready = WorkoutCameraFixtures.viewState(frameID: "camera-ready").visual
        let active = WorkoutCameraFixtures.viewState(frameID: "camera-active").visual

        assertRGB(WorkoutJointOverlayView.stateColor(for: ready), red: 185, green: 162, blue: 255)
        assertRGB(WorkoutJointOverlayView.stateColor(for: active), red: 185, green: 162, blue: 255)
    }

    func testUnemphasizedTrackedJointsAreWhite() {
        assertRGB(WorkoutJointOverlayView.jointColor(isStale: false, isEmphasized: false, isAtEndPosition: false),
                 red: 255, green: 255, blue: 255)
    }

    func testEndPositionAndCueJointsKeepTheirEmphasisColors() {
        assertRGB(WorkoutJointOverlayView.jointColor(isStale: false, isEmphasized: false, isAtEndPosition: true),
                 red: 79, green: 222, blue: 163)
        assertRGB(WorkoutJointOverlayView.jointColor(isStale: false, isEmphasized: true, isAtEndPosition: false),
                 red: 255, green: 194, blue: 61)
    }

    private func assertRGB(_ color: Color, red: Int, green: Int, blue: Int,
                           file: StaticString = #filePath, line: UInt = #line) {
        let resolved = UIColor(color).cgColor.components ?? []
        XCTAssertGreaterThanOrEqual(resolved.count, 3, file: file, line: line)
        XCTAssertEqual(Int((resolved[0] * 255).rounded()), red, file: file, line: line)
        XCTAssertEqual(Int((resolved[1] * 255).rounded()), green, file: file, line: line)
        XCTAssertEqual(Int((resolved[2] * 255).rounded()), blue, file: file, line: line)
    }
}
