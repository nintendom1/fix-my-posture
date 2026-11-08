import XCTest
@testable import PostureAnalysisApp

private struct ApprovedMovementFixture: Codable {
    struct Provenance: Codable {
        let kind: String
    }

    let schemaVersion: Int
    let executionMode: MovementLabMode
    let provenance: Provenance
    let plan: MovementPlan
    let result: MovementScenarioResult
}

/// Runs every human-approved Movement Lab fixture through its recorded execution path (#133).
@MainActor
final class MovementLabRegressionTests: XCTestCase {
    func testApprovedFixturesRegenerateAndPassFrozenAssertions() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fixtureDirectory = testsDirectory.appendingPathComponent("Fixtures/MovementScenarios/approved", isDirectory: true)
        guard FileManager.default.fileExists(atPath: fixtureDirectory.path) else { return }
        guard let enumerator = FileManager.default.enumerator(at: fixtureDirectory,
                                                              includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                                                              options: [.skipsHiddenFiles]) else {
            return XCTFail("Could not enumerate approved Movement Lab fixtures.")
        }

        var fixtureURLs: [URL] = []
        while let item = enumerator.nextObject() {
            guard let url = item as? URL, url.pathExtension == "json" else { continue }
            fixtureURLs.append(url)
        }
        fixtureURLs.sort { $0.path < $1.path }

        for fixtureURL in fixtureURLs {
            let fileValues = try fixtureURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard fileValues.isRegularFile == true, fileValues.isSymbolicLink != true else {
                XCTFail("Approved fixture must be a regular JSON file: \(fixtureURL.lastPathComponent)")
                continue
            }
            let data = try Data(contentsOf: fixtureURL)
            let fixture = try JSONDecoder().decode(ApprovedMovementFixture.self, from: data)
            XCTAssertEqual(fixture.schemaVersion, 1, fixtureURL.lastPathComponent)
            XCTAssertTrue(["developer-approved", "orchestrator-seeded"].contains(fixture.provenance.kind),
                          fixtureURL.lastPathComponent)
            XCTAssertEqual(fixture.plan.scenarios.count, 1, "Each fixture must freeze exactly one scenario.")
            guard let scenario = fixture.plan.scenarios.first else {
                XCTFail("Approved fixture has no scenario: \(fixtureURL.lastPathComponent)")
                continue
            }
            XCTAssertEqual(fixture.result.scenarioID, scenario.id, fixtureURL.lastPathComponent)
            XCTAssertEqual(fixture.result.revision, scenario.revision, fixtureURL.lastPathComponent)
            XCTAssertEqual(fixture.result.outcome, .passed, "Only passing approved results can enter CI.")
            XCTAssertFalse(scenario.assertions.isEmpty, "Approved fixtures require frozen assertions.")

            let materialization = MovementGenerator.materialize(plan: fixture.plan, scenario: scenario)
            XCTAssertTrue(materialization.isValid, materialization.invalidReasons.joined(separator: ", "))
            guard let generated = replay(fixture) else {
                XCTFail("Movement Lab did not produce a result for \(fixtureURL.lastPathComponent).")
                continue
            }
            XCTAssertEqual(generated.scenarioID, scenario.id)
            XCTAssertEqual(generated.revision, scenario.revision)
            XCTAssertEqual(generated.outcome, .passed, "Frozen assertions must pass for \(fixtureURL.lastPathComponent).")
            XCTAssertEqual(generated.observed, fixture.result.observed, "Observed values drifted for \(fixtureURL.lastPathComponent).")
            XCTAssertEqual(generated.assertionResults, fixture.result.assertionResults,
                           "Frozen assertion results drifted for \(fixtureURL.lastPathComponent).")
            XCTAssertTrue(generated.assertionResults.allSatisfy(\.passed), fixtureURL.lastPathComponent)
        }
    }

    func testCoachFixtureReplaysSpokenCueAssertionInStoredMode() throws {
        var scenario = try XCTUnwrap(MovementPresets.airSquat().scenarios.first { $0.id == "canonical" })
        scenario.assertions = [.spokenCue(textContains: "Set 1 of 2", present: true)]
        var plan = MovementPresets.airSquat()
        plan.scenarios = [scenario]

        let pipelineResult = try XCTUnwrap(MovementLabRunner.run(plan: plan, mode: .pipeline).results.first)
        XCTAssertEqual(pipelineResult.outcome, .inconclusive)
        let coachResult = try XCTUnwrap(MovementLabRunner.run(plan: plan, mode: .coach).results.first)
        XCTAssertEqual(coachResult.outcome, .passed)

        let fixture = ApprovedMovementFixture(schemaVersion: 1, executionMode: .coach,
            provenance: .init(kind: "developer-approved"), plan: plan, result: coachResult)
        let encodedFixture = try JSONEncoder().encode(fixture)
        let decodedFixture = try JSONDecoder().decode(ApprovedMovementFixture.self, from: encodedFixture)
        let replayed = try XCTUnwrap(replay(decodedFixture))
        XCTAssertEqual(replayed.outcome, .passed)
        XCTAssertEqual(replayed.observed, coachResult.observed)
        XCTAssertEqual(replayed.assertionResults, coachResult.assertionResults)
    }

    private func replay(_ fixture: ApprovedMovementFixture) -> MovementScenarioResult? {
        MovementLabRunner.run(plan: fixture.plan, mode: fixture.executionMode).results.first
    }
}
