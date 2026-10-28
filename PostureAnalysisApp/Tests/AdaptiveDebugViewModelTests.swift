import AdaptiveTraining
import Foundation
import XCTest
@testable import PostureAnalysisApp

final class AdaptiveDebugViewModelTests: XCTestCase {
    @MainActor
    func testRefreshLoadsSnapshotAndWritesDeterministicExportNameAndContents() async throws {
        let snapshot = makeSnapshot()
        let provider = FakeAdaptiveDebugProvider(snapshot: snapshot)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = AdaptiveDebugViewModel(provider: provider, now: { FixedClock.date },
                                               timeZone: FixedClock.timeZone, exportDirectory: directory)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.snapshot, snapshot)
        XCTAssertNil(viewModel.errorMessage)
        let exportURL = try XCTUnwrap(viewModel.exportURL)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = FixedClock.timeZone
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        XCTAssertEqual(exportURL.lastPathComponent, "FMP Adaptive \(formatter.string(from: FixedClock.date)).json")
        let fileData = try Data(contentsOf: exportURL)
        XCTAssertEqual(try AdaptiveExport.decode(fileData), snapshot)
    }

    @MainActor
    func testThrowingProviderShowsAnErrorMessage() async {
        let provider = FakeAdaptiveDebugProvider(error: NSError(domain: "AdaptiveDebug", code: 1,
                                                                 userInfo: [NSLocalizedDescriptionKey: "Snapshot failed."]))
        let viewModel = AdaptiveDebugViewModel(provider: provider, now: { FixedClock.date },
                                               timeZone: FixedClock.timeZone)

        await viewModel.refresh()

        XCTAssertNil(viewModel.snapshot)
        XCTAssertTrue(viewModel.errorMessage?.contains("Snapshot failed.") == true)
    }

    @MainActor
    func testCopyWritesTheSameJSONAsTheExport() async throws {
        let snapshot = makeSnapshot()
        var copied: String?
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let viewModel = AdaptiveDebugViewModel(provider: FakeAdaptiveDebugProvider(snapshot: snapshot),
                                               now: { FixedClock.date }, timeZone: FixedClock.timeZone,
                                               exportDirectory: directory,
                                               copy: { copied = $0 })

        await viewModel.refresh()
        viewModel.copyJSON()

        let json = try XCTUnwrap(viewModel.exportedJSON)
        XCTAssertEqual(copied, json)
        XCTAssertTrue(viewModel.didCopy)
        XCTAssertEqual(try AdaptiveExport.decode(Data(json.utf8)), snapshot)
    }

    @MainActor
    func testMissingProviderIsAnEmptyState() async {
        let viewModel = AdaptiveDebugViewModel(provider: nil, now: { FixedClock.date },
                                               timeZone: FixedClock.timeZone)

        await viewModel.refresh()

        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertNil(viewModel.snapshot)
        XCTAssertNil(viewModel.exportURL)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testRefreshReplacesTheExportAndResetsCopyState() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = makeSnapshot()
        let provider = FakeAdaptiveDebugProvider(snapshot: first)
        let viewModel = AdaptiveDebugViewModel(provider: provider, now: { FixedClock.date },
                                               timeZone: FixedClock.timeZone, exportDirectory: directory,
                                               copy: { _ in })
        await viewModel.refresh()
        viewModel.copyJSON()
        XCTAssertTrue(viewModel.didCopy)

        let second = Self.emptySnapshot()
        provider.snapshot = second
        await viewModel.refresh()

        XCTAssertFalse(viewModel.didCopy)
        XCTAssertEqual(viewModel.snapshot, second)
        let exportURL = try XCTUnwrap(viewModel.exportURL)
        XCTAssertEqual(try AdaptiveExport.decode(Data(contentsOf: exportURL)), second,
                       "The same-minute export file is rewritten with the newer snapshot.")
        XCTAssertEqual(try AdaptiveExport.decode(Data(XCTUnwrap(viewModel.exportedJSON).utf8)), second)
    }

    @MainActor
    func testFailuresAfterASuccessClearTheOldExportAndARetryRecovers() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = makeSnapshot()
        let provider = FakeAdaptiveDebugProvider(snapshot: snapshot)
        let viewModel = AdaptiveDebugViewModel(provider: provider, now: { FixedClock.date },
                                               timeZone: FixedClock.timeZone, exportDirectory: directory)
        await viewModel.refresh()
        XCTAssertNotNil(viewModel.exportURL)

        provider.error = NSError(domain: "AdaptiveDebug", code: 2,
                                 userInfo: [NSLocalizedDescriptionKey: "Store unavailable."])
        await viewModel.refresh()
        XCTAssertNil(viewModel.snapshot)
        XCTAssertNil(viewModel.exportURL)
        XCTAssertNil(viewModel.exportedJSON)
        XCTAssertEqual(viewModel.errorMessage, "Store unavailable.")

        provider.error = nil
        await viewModel.refresh()
        XCTAssertEqual(viewModel.snapshot, snapshot)
        XCTAssertNotNil(viewModel.exportURL)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testAnExportWriteFailureKeepsTheSnapshotAndShowsTheError() async throws {
        // A regular file where the export directory should be, so creating the directory fails.
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("not a directory".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let snapshot = makeSnapshot()
        let viewModel = AdaptiveDebugViewModel(provider: FakeAdaptiveDebugProvider(snapshot: snapshot),
                                               now: { FixedClock.date }, timeZone: FixedClock.timeZone,
                                               exportDirectory: blocker.appendingPathComponent("exports"))

        await viewModel.refresh()

        XCTAssertEqual(viewModel.snapshot, snapshot)
        XCTAssertNil(viewModel.exportURL)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testEffortLabelsAreReadable() {
        XCTAssertEqual(AdaptiveDebugScreen.effortLabel(.tooHard), "Too Hard")
        XCTAssertEqual(AdaptiveDebugScreen.effortLabel(.okay), "Okay")
        XCTAssertEqual(AdaptiveDebugScreen.effortLabel(nil), "Not rated")
    }

    @MainActor
    private func makeSnapshot() -> AdaptiveSnapshot {
        let start = RungDose(variant: VariantID(rawValue: "push.wall_push_up"), dose: .reps(3))
        let calibration = CalibrationSessionRecord(id: UUID(), kind: .initial,
                                                   startedAt: FixedClock.date.addingTimeInterval(-3_600),
                                                   endedAt: FixedClock.date.addingTimeInterval(-1_800),
                                                   status: .committed, families: [.push],
                                                   startingPoints: [CalibrationStart(family: .push, start: start)])
        let evidence = AdaptiveEvidence(id: UUID(), recordedAt: FixedClock.date, source: .manual, family: .push,
                                        variant: start.variant, prescribed: .reps(3), confirmed: .reps(0),
                                        confirmation: .user,
                                        tracker: TrackerObservation(status: .lost, observed: .reps(0)),
                                        effort: .tooHard, completion: .stoppedEarly)
        let facts = AdaptiveFacts(evidence: [evidence], calibrations: [calibration])
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = FixedClock.timeZone
        let builtIDs = Set(ProgressionCatalog.v1.families.flatMap { $0.rungs.map(\.exerciseID) })
        return AdaptiveReplay.snapshot(facts: facts, builtExerciseIDs: builtIDs, parameters: .standard,
                                       calendar: calendar, asOf: FixedClock.date, appVersion: "test")
    }

    @MainActor
    private final class FakeAdaptiveDebugProvider: AdaptiveDebugProviding {
        var snapshot: AdaptiveSnapshot
        var error: Error?

        init(snapshot: AdaptiveSnapshot? = nil, error: Error? = nil) {
            self.snapshot = snapshot ?? AdaptiveDebugViewModelTests.emptySnapshot()
            self.error = error
        }

        func adaptiveSnapshot(asOf now: Date) throws -> AdaptiveSnapshot {
            if let error { throw error }
            return snapshot
        }
    }

    @MainActor
    private static func emptySnapshot() -> AdaptiveSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = FixedClock.timeZone
        return AdaptiveReplay.snapshot(facts: .empty, builtExerciseIDs: [], parameters: .standard,
                                       calendar: calendar, asOf: FixedClock.date, appVersion: "test")
    }
}
