import XCTest
@testable import PostureAnalysisApp

/// Recording files on disk: writing, listing, pruning, and reading markers back.
final class WorkoutRecordingStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkoutRecordingStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testWriterWritesAJSONArrayWithOneRecordPerLine() throws {
        let url = directory.appendingPathComponent("a.json")
        let writer = try XCTUnwrap(FileWorkoutSessionWriter(url: url))
        writer.append(.object(("k", "header")))
        writer.append(.object(("k", "f"), ("t", 0.1)))
        let closed = expectation(description: "closed")
        var succeeded = false
        writer.close { result in
            // Everything appended before the close, and the closing bracket, is on disk here.
            succeeded = result && (try? String(contentsOf: url, encoding: .utf8))?.hasSuffix("]\n") == true
            closed.fulfill()
        }
        writer.append(.object(("k", "late")))
        wait(for: [closed], timeout: 5)
        writer.waitUntilIdle()

        XCTAssertTrue(succeeded)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(text, "[\n{\"k\":\"header\"},\n{\"k\":\"f\",\"t\":0.1}\n]\n")
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
        XCTAssertEqual(array.count, 2, "A closed recording is valid JSON.")
    }

    func testAnUnclosedRecordingStillReadsEveryRecord() throws {
        let url = directory.appendingPathComponent("open.json")
        let writer = try XCTUnwrap(FileWorkoutSessionWriter(url: url))
        writer.append(.object(("k", "header")))
        writer.append(.object(("k", "marker"), ("t", 2)))
        writer.drain()
        var records: [String] = []

        WorkoutRecordingFile.forEachLine(in: url) { records.append($0) }

        XCTAssertEqual(records, [#"{"k":"header"}"#, #"{"k":"marker","t":2}"#],
                       "A crash leaves the closing bracket missing but every record readable.")
        writer.close { _ in }
        writer.waitUntilIdle()
    }

    func testAnEmptyRecordingIsAnEmptyArray() throws {
        let url = directory.appendingPathComponent("empty.json")
        let writer = try XCTUnwrap(FileWorkoutSessionWriter(url: url))
        writer.close { _ in }
        writer.waitUntilIdle()

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "[\n]\n")
    }

    func testListReadsSummariesNewestFirstAndFallsBackWithoutOne() throws {
        let store = FileWorkoutRecordingStore(directory: directory)
        let older = summary(startedAt: 100)
        let newer = summary(startedAt: 200, markers: 1)
        for summary in [older, newer] {
            try writeFile(store, summary.id, "{\"k\":\"header\"}\n")
            store.saveSummary(summary)
        }
        let orphan = UUID()
        try writeFile(store, orphan, "{\"k\":\"header\"}\n")

        let listed = store.list()
        XCTAssertEqual(Array(listed.prefix(2).map(\.id)), [newer.id, older.id])
        let fallback = try XCTUnwrap(listed.first { $0.id == orphan })
        XCTAssertFalse(fallback.isComplete)
        XCTAssertEqual(listed.first?.byteCount, 15)
        XCTAssertEqual(listed.first?.markerCount, 1)
    }

    func testPruneKeepsTheNewestRecordingsRemovingUnmarkedOnesFirst() throws {
        let store = FileWorkoutRecordingStore(directory: directory, maximumRecordings: 4)
        let oldestMarked = summary(startedAt: 0, markers: 1)
        let oldUnmarked = summary(startedAt: 1)
        let newerMarked = summary(startedAt: 2, markers: 3)
        let newUnmarked = summary(startedAt: 3)
        let newestUnmarked = summary(startedAt: 4)
        let current = summary(startedAt: -5)
        for summary in [oldestMarked, oldUnmarked, newerMarked, newUnmarked, newestUnmarked, current] {
            try writeFile(store, summary.id, "x\n")
            store.saveSummary(summary)
        }

        store.prune(keeping: current.id)

        XCTAssertEqual(Set(store.list().map(\.id)), [current.id, oldestMarked.id, newerMarked.id, newestUnmarked.id],
                       "Unmarked recordings go first, oldest first; the one in progress stays.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: oldUnmarked.id).path))
    }

    func testPruneRemovesTheOldestMarkedOnceOnlyMarkedRemain() throws {
        let store = FileWorkoutRecordingStore(directory: directory, maximumRecordings: 2)
        let marked = (0..<3).map { summary(startedAt: Double($0), markers: 1) }
        let current = summary(startedAt: -1)
        for summary in marked + [current] {
            try writeFile(store, summary.id, "x\n")
            store.saveSummary(summary)
        }

        store.prune(keeping: current.id)

        XCTAssertEqual(Set(store.list().map(\.id)), [current.id, marked[2].id])
    }

    func testRecordingsThatNeverEndedAreCountedFromTheirFile() throws {
        let store = FileWorkoutRecordingStore(directory: directory)
        let crashed = UUID()
        let missing = UUID()
        let file = [
            #"{"k":"header","schema":"fmp.workout-session/1"}"#,
            #"{"k":"pipe","t":0.1,"control":"exercise","exercise":"shoulder_press","epoch":0}"#,
            #"{"k":"f","t":0.2,"j":[]}"#,
            #"{"k":"f","t":0.3,"j":[]}"#,
            #"{"k":"marker","t":0.4,"id":"A","source":"tap"}"#,
            #"{"k":"f","t":0.5,"j":[]}"#
        ].joined(separator: "\n") + "\n"
        for id in [crashed, missing] { try writeFile(store, id, file) }
        // The summary written when the recording began, never updated.
        store.saveSummary(WorkoutRecordingSummary(id: crashed, startedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                                  endedAt: nil, title: "Upper Body", exerciseIDs: [], frameCount: 0,
                                                  markerCount: 0, isComplete: false))

        let listed = Dictionary(uniqueKeysWithValues: store.list().map { ($0.id, $0) })

        for id in [crashed, missing] {
            let recovered = try XCTUnwrap(listed[id])
            XCTAssertEqual(recovered.markerCount, 1, "A marker in the file must protect the recording.")
            XCTAssertEqual(recovered.frameCount, 3)
            XCTAssertEqual(recovered.exerciseIDs, ["shoulder_press"])
            XCTAssertFalse(recovered.isComplete)
            XCTAssertEqual(recovered.isRecovered, true)
        }
        XCTAssertEqual(listed[crashed]?.title, "Upper Body")
    }

    func testTheRecordingInProgressIsNotRecoveredWhilePruning() throws {
        let store = FileWorkoutRecordingStore(directory: directory)
        let current = summary(startedAt: 0)
        var inProgress = current
        inProgress.isComplete = false
        try writeFile(store, current.id, #"{"k":"marker","t":1,"id":"A","source":"tap"}"# + "\n")
        store.saveSummary(inProgress)

        store.prune(keeping: current.id)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let saved = try decoder.decode(WorkoutRecordingSummary.self, from: Data(contentsOf: directory
            .appendingPathComponent("\(current.id.uuidString).summary.json")))
        XCTAssertNil(saved.isRecovered, "The recorder still owns this summary.")
    }

    func testRecordingsFolderIsExcludedFromBackups() throws {
        let store = FileWorkoutRecordingStore(directory: directory)
        _ = try XCTUnwrap(store.makeWriter(for: UUID()))

        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testDeleteRemovesTheFileAndItsSummary() throws {
        let store = FileWorkoutRecordingStore(directory: directory)
        let recording = summary(startedAt: 1)
        try writeFile(store, recording.id, "x\n")
        store.saveSummary(recording)

        store.delete(recording.id)

        XCTAssertTrue(store.list().isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testOlderJSONLinesRecordingsAreConvertedWhenListed() throws {
        let store = FileWorkoutRecordingStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var ids: [UUID] = []
        for legacyExtension in ["jsonl", "fmpsession"] {
            let id = UUID()
            ids.append(id)
            try "{\"k\":\"header\"}\n{\"k\":\"marker\",\"t\":1,\"id\":\"A\"}\n".write(
                to: directory.appendingPathComponent("\(id.uuidString).\(legacyExtension)"), atomically: true, encoding: .utf8)
        }

        XCTAssertEqual(Set(store.list().map(\.id)), Set(ids))
        for id in ids {
            let url = store.fileURL(for: id)
            XCTAssertEqual(url.pathExtension, "json")
            let array = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
            XCTAssertEqual(array.map { $0["k"] as? String }, ["header", "marker"])
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".jsonl") || $0.hasSuffix(".fmpsession") }
        XCTAssertTrue(leftovers.isEmpty)
        XCTAssertEqual(store.list().first { $0.id == ids[0] }?.markerCount, 1, "Markers survive the conversion.")
    }

    func testLineReaderDropsBracketsAndCommasAndACutOffLastLine() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cutOff = directory.appendingPathComponent("cut.json")
        try "[\n{\"k\":\"header\"},\n{\"k\":\"f\",\"t\":0.25,\"j\":[]},\n{\"k\":\"marker\",\"t\":2,\"sou".write(
            to: cutOff, atomically: true, encoding: .utf8)
        var lines: [String] = []
        WorkoutRecordingFile.forEachLine(in: cutOff) { lines.append($0) }

        XCTAssertEqual(lines, [#"{"k":"header"}"#, #"{"k":"f","t":0.25,"j":[]}"#])
        XCTAssertEqual(WorkoutRecordingFile.frameTime(lines[1]), 0.25)
        XCTAssertNil(WorkoutRecordingFile.frameTime(lines[0]))
    }

    // MARK: - Helpers

    private func summary(startedAt: TimeInterval, markers: Int = 0) -> WorkoutRecordingSummary {
        WorkoutRecordingSummary(id: UUID(), startedAt: Date(timeIntervalSince1970: 1_800_000_000 + startedAt),
                                endedAt: nil, title: "Workout", exerciseIDs: [], frameCount: 0, markerCount: markers,
                                isComplete: true)
    }

    private func writeFile(_ store: FileWorkoutRecordingStore, _ id: UUID, _ text: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try text.write(to: store.fileURL(for: id), atomically: true, encoding: .utf8)
    }
}
