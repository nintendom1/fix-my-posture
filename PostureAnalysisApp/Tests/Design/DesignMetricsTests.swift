import XCTest
import SwiftUI

final class DesignMetricsTests: XCTestCase {
    private let exemptions: [String: [String: String]] = [
        "train": [
            "statusBar": "The iOS status bar belongs to the snapshot window, outside TrainHomeScreen.",
            "train.hero.lastDone": "Phase 4.4 adds routine rotation and last-done history; this phase reserves its space.",
            "tabbar": "The native TabView owns the tab bar; TrainHomeScreen does not lay it out."
        ],
        "routines": [
            "statusBar": "The iOS status bar belongs to the snapshot window, outside RoutinesScreen.",
            "tabbar": "The native TabView owns the tab bar; RoutinesScreen does not lay it out."
        ],
        "routine": [
            "statusBar": "The iOS status bar belongs to the snapshot window, outside RoutineDetailScreen.",
            "routine.summary": "Phase 4.4 adds duration estimates; the detail summary omits the about X min segment.",
            "routine.actions.remind": "Remind me deferred.",
            "routine.actions.duplicate": "Remind me deferred.",
            "routine.actions.delete": "Remind me deferred.",
            "tabbar": "The native TabView owns the tab bar; RoutineDetailScreen does not lay it out."
        ],
        "editor": [
            "statusBar": "The iOS status bar belongs to the snapshot window, outside RoutineEditorScreen.",
            "editor.time": "Phase 4.4 adds routine duration estimates; the editor shows no time estimate.",
            "tabbar": "RoutineEditorScreen hides the native tab bar while the editor is open."
        ],
        "editor-picker": [
            "statusBar": "The iOS status bar belongs to the snapshot window, outside RoutineEditorScreen.",
            "tabbar": "The native TabView owns the tab bar; the picker sheet covers the native tab bar."
        ],
        "editor-new": [
            "statusBar": "The iOS status bar belongs to the snapshot window, outside RoutineEditorScreen.",
            "editor.time": "Phase 4.4 adds routine duration estimates; the editor shows no time estimate.",
            "tabbar": "RoutineEditorScreen hides the native tab bar while the editor is open."
        ],
        "library": [
            "statusBar": "The iOS status bar belongs to the snapshot window, outside LibraryScreen.",
            "tabbar": "The native TabView owns the tab bar; LibraryScreen does not lay it out."
        ],
        "exercise": [
            "statusBar": "The iOS status bar belongs to the snapshot window, outside ExerciseDetailScreen.",
            "exercise.favorite": "The favourite heart is deferred.",
            "tabbar": "The native TabView owns the tab bar; ExerciseDetailScreen does not lay it out."
        ],
        "camera-ready": [
            "statusBar": "The iOS status bar belongs to the snapshot window, outside WorkoutCameraScreen."
        ],
        "camera-active": [
            "statusBar": "The iOS status bar belongs to the snapshot window, outside WorkoutCameraScreen."
        ],
        "camera-paused": [
            "statusBar": "The iOS status bar belongs to the snapshot window, outside WorkoutCameraScreen."
        ],
        "camera-tip": [
            "statusBar": "The iOS status bar belongs to the snapshot window, outside WorkoutCameraScreen."
        ],
        "camera-rest-coach-muted": [
            "statusBar": "The iOS status bar belongs to the snapshot window, outside WorkoutCameraScreen."
        ],
        "camera-lost-mic-off": [
            "statusBar": "The iOS status bar belongs to the snapshot window, outside WorkoutCameraScreen."
        ],
        "camera-tilt": [
            "statusBar": "The iOS status bar belongs to the snapshot window, outside WorkoutCameraScreen."
        ],
        "complete": [
            "statusBar": "The iOS status bar belongs to the snapshot window, outside WorkoutCompleteScreen."
        ],
        "progress": [
            "statusBar": "The iOS status bar belongs to the snapshot window, outside ProgressScreen.",
            "tabbar": "The native TabView owns the tab bar; ProgressScreen does not lay it out."
        ],
        "history": [
            "statusBar": "The iOS status bar belongs to the snapshot window, outside HistoryScreen.",
            "tabbar": "The native TabView owns the tab bar; HistoryScreen does not lay it out."
        ],
        "posture": [
            "statusBar": "The iOS status bar belongs to the snapshot window, outside PostureHomeScreen.",
            "tabbar": "The native TabView owns the tab bar; PostureHomeScreen does not lay it out."
        ],
        "assessment": [
            "statusBar": "The iOS status bar belongs to the snapshot window, outside AssessmentScreen.",
            "tabbar": "The native TabView owns the tab bar; AssessmentScreen does not lay it out.",
            "assessment.share": "Share is deferred in this phase."
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
    func testRoutinesFrame() throws {
        let result = try SnapshotHost.render(RoutinesFixtures.designTabView, frameId: "routines", testCase: self)
        try assertAnchors(frameId: "routines", actual: result.snapshotMeasuredAnchors)
    }

    @MainActor
    func testRoutineDetailFrame() throws {
        let result = try SnapshotHost.render(RoutineDetailFixtures.designTabView, frameId: "routine", testCase: self)
        try assertAnchors(frameId: "routine", actual: result.snapshotMeasuredAnchors)
    }

    @MainActor
    func testRoutineEditorFrame() throws {
        let result = try SnapshotHost.render(RoutineEditorFixtures.designTabView, frameId: "editor", testCase: self)
        try assertAnchors(frameId: "editor", actual: result.snapshotMeasuredAnchors)
    }

    @MainActor
    func testRoutineEditorPickerFrame() throws {
        let result = try SnapshotHost.render(RoutineEditorFixtures.pickerSheet, frameId: "editor-picker", testCase: self)
        try assertAnchors(frameId: "editor-picker", actual: result.snapshotMeasuredAnchors)
    }

    @MainActor
    func testNewRoutineFrame() throws {
        let result = try SnapshotHost.render(RoutineEditorFixtures.newRoutineTabView, frameId: "editor-new", testCase: self)
        try assertAnchors(frameId: "editor-new", actual: result.snapshotMeasuredAnchors)
    }

    @MainActor
    func testLibraryFrame() throws {
        let result = try SnapshotHost.render(LibraryFixtures.designTabView, frameId: "library", testCase: self)
        try assertAnchors(frameId: "library", actual: result.snapshotMeasuredAnchors)
    }

    @MainActor
    func testExerciseDetailFrame() throws {
        let result = try SnapshotHost.render(ExerciseDetailFixtures.designTabView, frameId: "exercise", testCase: self)
        try assertAnchors(frameId: "exercise", actual: result.snapshotMeasuredAnchors)
    }

    @MainActor
    func testWorkoutCameraReadyFrame() throws { try assertCameraFrame("camera-ready") }

    @MainActor
    func testWorkoutCameraActiveFrame() throws { try assertCameraFrame("camera-active") }

    @MainActor
    func testWorkoutCameraPausedFrame() throws { try assertCameraFrame("camera-paused") }

    @MainActor
    func testWorkoutCameraTipFrame() throws { try assertCameraFrame("camera-tip") }

    @MainActor
    func testWorkoutCameraRestCoachMutedFrame() throws { try assertCameraFrame("camera-rest-coach-muted") }

    @MainActor
    func testWorkoutCameraLostMicOffFrame() throws { try assertCameraFrame("camera-lost-mic-off") }

    @MainActor
    func testWorkoutCameraTiltFrame() throws { try assertCameraFrame("camera-tilt") }

    @MainActor
    func testWorkoutCompleteFrame() throws {
        let result = try SnapshotHost.render(WorkoutCompleteFixtures.screen(), frameId: "complete", testCase: self)
        try assertAnchors(frameId: "complete", actual: result.snapshotMeasuredAnchors)
    }

    @MainActor
    func testProgressFrame() throws {
        let result = try SnapshotHost.render(ProgressFixtures.designTabView(), frameId: "progress", testCase: self)
        try assertAnchors(frameId: "progress", actual: result.snapshotMeasuredAnchors)
    }

    @MainActor
    func testHistoryFrame() throws {
        let result = try SnapshotHost.render(HistoryFixtures.designTabView(), frameId: "history", testCase: self)
        try assertAnchors(frameId: "history", actual: result.snapshotMeasuredAnchors)
    }

    @MainActor
    func testPostureFrame() throws {
        let result = try SnapshotHost.render(PostureFixtures.designTabView(), frameId: "posture", testCase: self)
        try assertAnchors(frameId: "posture", actual: result.snapshotMeasuredAnchors)
    }

    @MainActor
    func testAssessmentFrame() throws {
        let result = try SnapshotHost.render(AssessmentFixtures.designTabView(), frameId: "assessment", testCase: self)
        try assertAnchors(frameId: "assessment", actual: result.snapshotMeasuredAnchors)
    }

    @MainActor
    func testTrainScrolledBy200KeepsCompactHeaderAndSettingsReachable() throws {
        let result = try SnapshotHost.render(TrainHomeFixtures.scrolledTabView, frameId: "train-scrolled", testCase: self)
        let compactBar = try XCTUnwrap(result.snapshotMeasuredAnchors["train.compactBar"])
        let settings = try XCTUnwrap(result.snapshotMeasuredAnchors["train.compactBar.settings"])
        XCTAssertEqual(compactBar.minY, 54, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(compactBar.minY, 54)
        XCTAssertLessThanOrEqual(compactBar.maxY, DesignWindow.fixedSize.height - 86)
        XCTAssertGreaterThanOrEqual(settings.minX, 0)
        XCTAssertLessThanOrEqual(settings.maxX, DesignWindow.fixedSize.width)
        XCTAssertGreaterThanOrEqual(settings.minY, 54)
        XCTAssertLessThanOrEqual(settings.maxY, DesignWindow.fixedSize.height - 86)
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

    @MainActor
    private func assertCameraFrame(_ frameID: String) throws {
        let result = try SnapshotHost.render(WorkoutCameraFixtures.screen(frameID: frameID),
                                             frameId: frameID,
                                             testCase: self)
        try assertAnchors(frameId: frameID, actual: result.snapshotMeasuredAnchors)
    }
}
