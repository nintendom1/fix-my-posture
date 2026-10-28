import Foundation
import XCTest
@testable import AdaptiveTraining

final class ReplayComparisonTests: XCTestCase {
    func testSameParametersReportNoDecisionChanges() {
        let snapshot = makeSnapshot()

        let comparison = ReplayComparison.compare(snapshot, parameters: snapshot.parameters)

        XCTAssertTrue(comparison.report.contains("No decisions change."))
    }

    func testCandidateParametersListChangedHoldAsAnIncrease() throws {
        let evidence = Fixtures.evidence(id: 102, day: 1, effort: .easy)
        let snapshot = makeSnapshot(evidence: evidence)
        var candidate = PolicyParameters.standard
        candidate.easyStreakToIncrease = 1

        let comparison = ReplayComparison.compare(snapshot, parameters: candidate)

        XCTAssertTrue(comparison.report.contains("easyStreakToIncrease: 2 → 1"))
        XCTAssertTrue(comparison.report.contains("push"))
        XCTAssertTrue(comparison.report.contains(String(evidence.id.uuidString.prefix(8)).lowercased()))
        XCTAssertTrue(comparison.report.contains("hold/push.wall_push_up × 3 reps → increaseDose/push.wall_push_up × 4 reps"))
    }

    func testUnknownTimeZoneFallsBackToUTCAndExplainsIt() {
        let original = makeSnapshot()
        let snapshot = AdaptiveSnapshot(generatedAt: original.generatedAt, appVersion: original.appVersion,
                                        timeZone: "Unknown/ExportZone", policyVersion: original.policyVersion,
                                        parameters: original.parameters, catalog: original.catalog,
                                        availability: original.availability, today: original.today,
                                        families: original.families, profile: original.profile,
                                        events: original.events, facts: original.facts)

        let comparison = ReplayComparison.compare(snapshot, parameters: nil)

        XCTAssertTrue(comparison.report.contains("Unknown/ExportZone is unknown; replayed with UTC."))
    }

    private func makeSnapshot(evidence: AdaptiveEvidence? = nil) -> AdaptiveSnapshot {
        let facts = AdaptiveFacts(evidence: evidence.map { [$0] } ?? [], calibrations: [Fixtures.calibration()])
        return AdaptiveReplay.snapshot(facts: facts, catalog: Fixtures.catalog,
                                       builtExerciseIDs: Fixtures.allBuiltExerciseIDs, parameters: .standard,
                                       calendar: Fixtures.calendar, asOf: Fixtures.date(day: 20),
                                       appVersion: "test")
    }
}
