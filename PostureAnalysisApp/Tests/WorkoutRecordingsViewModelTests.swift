import XCTest
@testable import PostureAnalysisApp

/// The developer Workout recordings page.
@MainActor
final class WorkoutRecordingsViewModelTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkoutRecordingsViewModelTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testToggleSavesThePreference() {
        let preferences = InMemoryPreferences()
        let viewModel = WorkoutRecordingsViewModel(store: MemoryWorkoutRecordingStore(), preferences: preferences,
                                                   shareDirectory: directory)
        XCTAssertFalse(viewModel.isRecordingEnabled)

        viewModel.isRecordingEnabled = true

        XCTAssertTrue(preferences.workoutRecordingEnabled)
    }

    func testDeleteUnmarkedKeepsRecordingsWithMarkers() {
        let store = MemoryWorkoutRecordingStore()
        let marked = summary(markers: 1)
        let unmarked = summary(markers: 0)
        store.saveSummary(marked)
        store.saveSummary(unmarked)
        let viewModel = WorkoutRecordingsViewModel(store: store, preferences: InMemoryPreferences(),
                                                   shareDirectory: directory)
        viewModel.refresh()
        XCTAssertEqual(viewModel.unmarkedCount, 1)

        viewModel.deleteUnmarked()

        XCTAssertEqual(viewModel.recordings.map(\.id), [marked.id])
        XCTAssertEqual(store.deleted, [unmarked.id])
    }

    func testShareFileNamesAreReadableAndUnique() {
        var recording = summary(markers: 0)
        recording.title = "Shoulders & Arms"
        let utc = TimeZone(identifier: "UTC")!
        let first = WorkoutRecordingsViewModel.shareFileName(recording, timeZone: utc)
        XCTAssertEqual(first, "FMP Shoulders & Arms 2027-01-15 0800.json")
        XCTAssertEqual(WorkoutRecordingsViewModel.shareFileName(recording, timeZone: utc, taken: [first]),
                       "FMP Shoulders & Arms 2027-01-15 0800 (2).json")
        recording.title = "Back/Posture: 1"
        XCTAssertEqual(WorkoutRecordingsViewModel.shareFileName(recording, timeZone: utc),
                       "FMP Back-Posture- 1 2027-01-15 0800.json")
    }

    func testSharingUsesTheReadableNameForTheSameFile() throws {
        let store = FileWorkoutRecordingStore(directory: directory.appendingPathComponent("store"))
        var recording = summary(markers: 0)
        recording.title = "Push-Up"
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try "{\"k\":\"header\"}\n".write(to: store.fileURL(for: recording.id), atomically: true, encoding: .utf8)
        store.saveSummary(recording)
        let viewModel = WorkoutRecordingsViewModel(store: store, preferences: InMemoryPreferences(),
                                                   timeZone: TimeZone(identifier: "UTC")!,
                                                   shareDirectory: directory.appendingPathComponent("share"))

        viewModel.refresh()

        let shared = viewModel.shareURL(for: recording.id)
        XCTAssertEqual(shared.lastPathComponent, "FMP Push-Up 2027-01-15 0800.json")
        XCTAssertEqual(try String(contentsOf: shared, encoding: .utf8), "{\"k\":\"header\"}\n")
    }

    func testCopyReportCopiesTheRecordingsReport() async throws {
        let store = FileWorkoutRecordingStore(directory: directory.appendingPathComponent("store"))
        var recording = summary(markers: 0)
        recording.title = "Push-Up"
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try WorkoutRecordingReportTests.fileText(WorkoutRecordingReportTests.sampleLines)
            .write(to: store.fileURL(for: recording.id), atomically: true, encoding: .utf8)
        store.saveSummary(recording)
        var copied: [String] = []
        let viewModel = WorkoutRecordingsViewModel(store: store, preferences: InMemoryPreferences(),
                                                   copy: { copied.append($0) },
                                                   shareDirectory: directory.appendingPathComponent("share"))
        viewModel.refresh()

        await viewModel.copyReport(of: recording.id)

        XCTAssertEqual(copied.count, 1)
        XCTAssertTrue(copied[0].hasPrefix("FMP workout report · Push-Up"), copied[0])
        XCTAssertTrue(copied[0].contains("Tracking lost at 0:13.3"))
        XCTAssertEqual(viewModel.copiedID, recording.id)
        XCTAssertNil(viewModel.copyingID)
    }

    private func summary(markers: Int) -> WorkoutRecordingSummary {
        WorkoutRecordingSummary(id: UUID(), startedAt: Date(timeIntervalSince1970: 1_800_000_000), endedAt: nil,
                                title: "Workout", exerciseIDs: [], frameCount: 0, markerCount: markers,
                                isComplete: true)
    }
}
