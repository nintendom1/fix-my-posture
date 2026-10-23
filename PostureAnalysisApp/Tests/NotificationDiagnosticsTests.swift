import Foundation
import XCTest
@testable import PostureAnalysisApp

final class NotificationEventLogTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotificationEventLogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRecordsMessagesWithTheirTimeInOrder() {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let log = FileNotificationEventLog(url: directory.appendingPathComponent("events.log"), now: { clock })

        log.record("first")
        clock.addTimeInterval(61)
        log.record("second")

        let lines = log.recentLines(10)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasSuffix(" first"))
        XCTAssertTrue(lines[1].hasSuffix(" second"))
        XCTAssertTrue(lines[0].hasPrefix(Date(timeIntervalSince1970: 1_800_000_000).eventLogDescription))
        XCTAssertTrue(lines[1].hasPrefix(Date(timeIntervalSince1970: 1_800_000_061).eventLogDescription))
    }

    func testKeepsOnlyTheNewestLinesAndSurvivesANewInstance() {
        let url = directory.appendingPathComponent("events.log")
        let log = FileNotificationEventLog(url: url, maximumLines: 3)
        for number in 1...5 { log.record("message \(number)") }

        XCTAssertEqual(log.recentLines(10).map { String($0.split(separator: " ", maxSplits: 2).last ?? "") },
                       ["message 3", "message 4", "message 5"])
        let reopened = FileNotificationEventLog(url: url, maximumLines: 3)
        XCTAssertEqual(reopened.recentLines(2).count, 2)
        reopened.record("message 6")
        XCTAssertTrue(reopened.recentLines(1)[0].hasSuffix("message 6"))
        XCTAssertEqual(reopened.recentLines(10).count, 3)
    }

    func testMissingFileReadsAsEmptyAndRecentLinesNeverGoNegative() {
        let log = FileNotificationEventLog(url: directory.appendingPathComponent("nothing-yet.log"))

        XCTAssertEqual(log.recentLines(5), [])
        XCTAssertEqual(log.recentLines(-1), [])
    }
}

@MainActor
final class NotificationDiagnosticsTests: XCTestCase {
    func testReportListsSettingsPendingDeliveredAndEventsAndFiltersReminders() {
        let snapshot = makeSnapshot()

        XCTAssertEqual(snapshot.pendingReminders.map(\.identifier),
                       [WorkoutReminderScheduleBuilder.identifierPrefix + "character.2026-10-24.0"])
        let report = snapshot.report
        for fragment in ["Settings:", "  Lock Screen: enabled", "Pending (2), soonest first:",
                         "Delivered and still in Notification Center (1):", "Recent events (1):",
                         "Shoulder Day · about 12 min", "reconcile: character style"] {
            XCTAssertTrue(report.contains(fragment), fragment)
        }
    }

    func testRefreshReadsTheProviderAndWritesTheReportFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let provider = FakeDiagnosticsProvider(snapshot: makeSnapshot())
        let viewModel = makeViewModel(diagnostics: provider, reportURL: url)

        XCTAssertTrue(viewModel.hasDiagnostics)
        XCTAssertNil(viewModel.diagnostics)

        await viewModel.refreshDiagnostics()

        XCTAssertEqual(viewModel.diagnostics, provider.result)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), provider.result.report)
        XCTAssertEqual(provider.callCount, 1)
    }

    func testSendingAlsoRefreshesTheDiagnostics() async {
        let provider = FakeDiagnosticsProvider(snapshot: makeSnapshot())
        let viewModel = makeViewModel(diagnostics: provider, reportURL: nil)

        await viewModel.send()

        XCTAssertEqual(provider.callCount, 1)
        XCTAssertEqual(viewModel.diagnostics, provider.result)
    }

    func testWithoutAProviderThereAreNoDiagnostics() async {
        let viewModel = makeViewModel(diagnostics: nil, reportURL: nil)

        await viewModel.refreshDiagnostics()

        XCTAssertFalse(viewModel.hasDiagnostics)
        XCTAssertNil(viewModel.diagnostics)
    }

    private func makeViewModel(
        diagnostics: (any NotificationDiagnosticsProviding)?, reportURL: URL?
    ) -> NotificationPreviewViewModel {
        NotificationPreviewViewModel(
            catalog: try? NotificationScenarioCatalog.bundled(bundle: Bundle(for: AppEnvironment.self)),
            preferences: InMemoryPreferences(),
            scheduler: FakePreviewScheduler(),
            openSettings: {},
            sleep: { _ in },
            diagnostics: diagnostics,
            diagnosticsReportURL: reportURL
        )
    }

    private func makeSnapshot() -> NotificationDiagnosticsSnapshot {
        let fire = Date(timeIntervalSince1970: 1_800_000_000)
        return NotificationDiagnosticsSnapshot(
            settings: ["Permission: authorized", "Lock Screen: enabled"],
            pending: [
                .init(identifier: WorkoutReminderScheduleBuilder.identifierPrefix + "character.2026-10-24.0",
                      title: "Shoulder Day · about 12 min", body: "Hey. Want to start one with me?", fireDate: fire),
                .init(identifier: WorkoutAcknowledgmentRequest.identifierPrefix + "abc",
                      title: "Nice work", body: "There we go.", fireDate: fire.addingTimeInterval(3))
            ],
            delivered: [.init(identifier: "x", title: "Old", body: "Old body", date: fire.addingTimeInterval(-60))],
            recentEvents: ["2026-10-23 08:17:20 reconcile: character style, scheduling 14 reminders, first at none"],
            generatedAt: fire
        )
    }
}

@MainActor
private final class FakeDiagnosticsProvider: NotificationDiagnosticsProviding {
    let result: NotificationDiagnosticsSnapshot
    private(set) var callCount = 0

    init(snapshot: NotificationDiagnosticsSnapshot) {
        result = snapshot
    }

    func snapshot() async -> NotificationDiagnosticsSnapshot {
        callCount += 1
        return result
    }
}
