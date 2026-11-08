import XCTest
@testable import AdaptiveTraining

@MainActor
final class CalibrationEngineTests: XCTestCase {
    private let shallow = Fixtures.shallowWall
    private let wall = Fixtures.wall
    private let incline = Fixtures.incline
    private let sit = VariantID(rawValue: "squat.sit_to_stand")
    private let air = VariantID(rawValue: "squat.air_squat")
    private let press = VariantID(rawValue: "overhead.shoulder_press")

    private let flowID = Fixtures.id(50)
    private let startedAt = Fixtures.date(day: 1, hour: 10)
    private let endedAt = Fixtures.date(day: 1, hour: 12)

    private struct Rig {
        let store: InMemoryAdaptiveTrainingStore
        let engine: AdaptiveTrainingEngine
    }

    private func makeRig(facts: AdaptiveFacts = .empty) -> Rig {
        let store = InMemoryAdaptiveTrainingStore(facts: facts)
        return Rig(store: store, engine: AdaptiveTrainingEngine(store: store, builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                                                calendar: Fixtures.calendar))
    }

    /// Records the current probe's evidence the way the app does (source calibration, this attempt's id), then reports
    /// it to the flow.
    private func rate(_ rig: Rig, _ flow: inout CalibrationFlow, _ effort: EffortFeedback, number: Int,
                      file: StaticString = #filePath, line: UInt = #line) throws {
        guard case .probe(let family, let rungDose, _) = flow.step else {
            return XCTFail("Not at a probe: \(flow.step)", file: file, line: line)
        }
        let amount = WorkAmount(rungDose.dose)
        try rig.engine.record(AdaptiveEvidence(
            id: Fixtures.id(100 + number), recordedAt: startedAt.addingTimeInterval(TimeInterval(60 * number)),
            source: .calibration, family: family, variant: rungDose.variant, calibrationID: flow.id,
            prescribed: rungDose.dose, confirmed: amount, confirmation: .user, tracker: .notTracked, effort: effort,
            completion: .completed))
        flow.probeResult(family: family, effort: effort, confirmed: amount)
    }

    /// The acceptance run: push and squat, with a harder sample for push.
    private func pushAndSquat(_ rig: Rig) throws -> CalibrationFlow {
        var flow = try rig.engine.startCalibration(kind: .initial, id: flowID, at: startedAt)
        flow.setEquipment([])
        try rig.engine.saveProgress(flow)
        flow.setFamilies([.push, .squat])
        flow.answerCloseness(family: .push, variant: wall)
        flow.answerCloseness(family: .squat, variant: air)
        try rig.engine.saveProgress(flow)

        try rate(rig, &flow, .easy, number: 1)
        try rate(rig, &flow, .okay, number: 2)
        try rate(rig, &flow, .okay, number: 3)
        return flow
    }

    private func stored(_ rig: Rig, _ id: UUID) throws -> CalibrationSessionRecord? {
        try rig.store.loadFacts().calibrations.first { $0.id == id }
    }

    // MARK: - Saving

    func testStartingSavesAnInProgressRecordThatChangesNothing() throws {
        let rig = makeRig()
        let flow = try rig.engine.startCalibration(kind: .initial, id: flowID, at: startedAt)

        let record = try XCTUnwrap(try stored(rig, flowID))
        XCTAssertEqual(record, flow.inProgressRecord)
        XCTAssertEqual(record.status, .inProgress)
        XCTAssertEqual(record.startedAt, startedAt)
        XCTAssertTrue(try rig.engine.profile().needsCalibration)
        XCTAssertEqual(try rig.engine.todaySession(asOf: Fixtures.date(day: 2)), .needsCalibration)
    }

    func testSavingProgressKeepsTheQuizAnswersWithoutChangingAnything() throws {
        let rig = makeRig()
        var flow = try rig.engine.startCalibration(kind: .initial, id: flowID, at: startedAt)
        flow.setEquipment([.dumbbells])
        flow.setFamilies([.push, .overhead])
        try rig.engine.saveProgress(flow)

        let record = try XCTUnwrap(try stored(rig, flowID))
        XCTAssertEqual(record.status, .inProgress)
        XCTAssertEqual(record.equipment, [.dumbbells])
        XCTAssertEqual(record.families, [.push, .overhead])
        XCTAssertEqual(record.startingPoints, [])
        XCTAssertTrue(try rig.engine.profile().needsCalibration)
        XCTAssertEqual(try rig.store.loadFacts().calibrations.count, 1, "The attempt is updated in place.")
    }

    // MARK: - Commit (push and squat end to end)

    func testPushAndSquatCalibrationCommitsStartingPointsThatReplayAsTheProfile() throws {
        let rig = makeRig()
        let flow = try pushAndSquat(rig)
        guard case .summary(let points) = flow.step else { return XCTFail("Expected a summary, got \(flow.step).") }
        XCTAssertEqual(points, [CalibrationStart(family: .push, start: RungDose(variant: incline, dose: .reps(1))),
                                CalibrationStart(family: .squat, start: RungDose(variant: sit, dose: .reps(2)))])

        // Samples alone change nothing.
        XCTAssertTrue(try rig.engine.profile().needsCalibration)
        XCTAssertEqual(try rig.engine.todaySession(asOf: Fixtures.date(day: 2)), .needsCalibration)

        let events = try rig.engine.commit(flow, at: endedAt)

        XCTAssertTrue(events.contains { $0.kind == .calibrationCompleted })
        let record = try XCTUnwrap(try stored(rig, flowID))
        XCTAssertEqual(record.status, .committed)
        XCTAssertEqual(record.startingPoints, points)
        XCTAssertEqual(record.endedAt, endedAt)

        let profile = try rig.engine.profile()
        XCTAssertEqual(profile.activeFamilies, [.push, .squat])
        XCTAssertEqual(profile.state(.push)?.current, RungDose(variant: incline, dose: .reps(1)))
        XCTAssertEqual(profile.state(.squat)?.current, RungDose(variant: sit, dose: .reps(2)))
        let pushComfort = profile.state(.push)?.comfortableDoses.map { "\($0.variant.rawValue) \($0.dose)" }
        XCTAssertEqual(pushComfort, ["push.incline_push_up 1 rep", "push.wall_push_up 2 reps"],
                       "The committed samples teach the policy which doses were comfortable.")
        let codes = Set(profile.transitions.flatMap(\.rationale.codes))
        XCTAssertTrue(codes.contains(.calibrationProbe))
        XCTAssertTrue(codes.contains(.calibrationCommitted))
        XCTAssertFalse(codes.contains(.calibrationNotCommitted))
        guard case .ready = try rig.engine.todaySession(asOf: Fixtures.date(day: 2)) else {
            return XCTFail("Today's Session should be ready once the starting points count.")
        }
    }

    func testProbeEvidenceIsStoredWithTheCalibrationSourceAndTheAttemptsID() throws {
        let rig = makeRig()
        _ = try pushAndSquat(rig)

        let evidence = try rig.store.loadFacts().evidence
        XCTAssertEqual(evidence.count, 3)
        XCTAssertTrue(evidence.allSatisfy { $0.source == .calibration && $0.calibrationID == flowID })
        XCTAssertEqual(evidence.map(\.variant), [wall, incline, sit])
    }

    func testTheEquipmentAnswerIsCommittedAndReplayed() throws {
        let rig = makeRig()
        var flow = try rig.engine.startCalibration(kind: .initial, id: flowID, at: startedAt)
        flow.setEquipment([.dumbbells])
        flow.setFamilies([.overhead])
        flow.answerCloseness(family: .overhead, variant: press)
        try rate(rig, &flow, .easy, number: 1)
        try rate(rig, &flow, .okay, number: 2)

        try rig.engine.commit(flow, at: endedAt)

        let profile = try rig.engine.profile()
        XCTAssertEqual(profile.equipment, [.dumbbells])
        XCTAssertEqual(profile.state(.overhead)?.current, RungDose(variant: press, dose: .reps(1)),
                       "Dumbbells make the shoulder press available as the harder sample.")
    }

    func testDecliningAHarderSampleCommitsTheEasySampleAtItsOwnDose() throws {
        let rig = makeRig()
        var flow = try rig.engine.startCalibration(kind: .initial, id: flowID, at: startedAt)
        flow.setEquipment([])
        flow.setFamilies([.squat])
        flow.answerCloseness(family: .squat, variant: nil)
        try rate(rig, &flow, .easy, number: 1)
        flow.declineHarderProbe(family: .squat)

        try rig.engine.commit(flow, at: endedAt)

        let profile = try rig.engine.profile()
        let partialSit = VariantID(rawValue: "squat.sit_to_stand.partial")
        XCTAssertEqual(profile.state(.squat)?.current, RungDose(variant: partialSit, dose: .reps(2)))
        XCTAssertEqual(try rig.store.loadFacts().evidence.count, 1, "Declining leaves no evidence: it is neutral.")
    }

    // MARK: - Abandon (invariant 7)

    func testAbandoningLeavesTheProfileUnchanged() throws {
        let rig = makeRig(facts: Fixtures.seededFacts(variant: wall, dose: .reps(3)))
        let before = try rig.engine.profile()
        let todayBefore = try rig.engine.todaySession(asOf: Fixtures.date(day: 3))
        XCTAssertEqual(before.state(.push)?.current, RungDose(variant: wall, dose: .reps(3)))

        let flow = try pushAndSquat(rig)
        guard case .summary = flow.step else { return XCTFail("Expected a summary, got \(flow.step).") }
        let events = try rig.engine.abandon(flow, at: endedAt)
        XCTAssertFalse(events.contains { $0.kind == .calibrationCompleted })

        let record = try XCTUnwrap(try stored(rig, flowID))
        XCTAssertEqual(record.status, .abandoned)
        XCTAssertEqual(record.startingPoints, [], "Leaving accepts nothing, even from the summary.")
        let after = try rig.engine.profile()
        XCTAssertEqual(after.states, before.states)
        XCTAssertEqual(after.activeFamilies, before.activeFamilies)
        XCTAssertEqual(after.equipment, before.equipment)
        XCTAssertEqual(try rig.engine.todaySession(asOf: Fixtures.date(day: 3)), todayBefore)
        XCTAssertTrue(Set(after.transitions.flatMap(\.rationale.codes)).contains(.calibrationNotCommitted),
                      "The samples stay on record, uncommitted.")
    }

    func testAbandoningAtTheQuizOrMidProbeLeavesTheProfileUnchanged() throws {
        for stopAfter in [0, 1, 2] {
            let rig = makeRig(facts: Fixtures.seededFacts(variant: wall, dose: .reps(3)))
            let before = try rig.engine.profile()
            var flow = try rig.engine.startCalibration(kind: .initial, id: flowID, at: startedAt)
            if stopAfter >= 1 {
                flow.setEquipment([])
                flow.setFamilies([.push])
                flow.answerCloseness(family: .push, variant: wall)
            }
            if stopAfter >= 2 { try rate(rig, &flow, .easy, number: 1) }

            try rig.engine.abandon(flow, at: endedAt)

            let after = try rig.engine.profile()
            XCTAssertEqual(after.states, before.states, "stopAfter \(stopAfter)")
            XCTAssertEqual(after.activeFamilies, before.activeFamilies, "stopAfter \(stopAfter)")
            XCTAssertEqual(try stored(rig, flowID)?.status, .abandoned, "stopAfter \(stopAfter)")
        }
    }

    // MARK: - Refusals

    func testCommittingBeforeTheSummaryThrowsAndSavesNothing() throws {
        let rig = makeRig()
        var flow = try rig.engine.startCalibration(kind: .initial, id: flowID, at: startedAt)
        flow.setEquipment([])
        flow.setFamilies([.push])
        flow.answerCloseness(family: .push, variant: nil)
        try rig.engine.saveProgress(flow)

        XCTAssertThrowsError(try rig.engine.commit(flow, at: endedAt)) { error in
            XCTAssertEqual(error as? AdaptiveTrainingEngineError, .calibrationNotAtSummary(flowID))
        }
        XCTAssertEqual(try stored(rig, flowID)?.status, .inProgress)
        XCTAssertTrue(try rig.engine.profile().needsCalibration)
    }

    func testCommittingAnEmptySummaryThrows() throws {
        let rig = makeRig()
        var flow = try rig.engine.startCalibration(kind: .initial, id: flowID, at: startedAt)
        flow.setEquipment([])
        flow.setFamilies([.push])
        flow.skipFamily(family: .push)

        XCTAssertThrowsError(try rig.engine.commit(flow, at: endedAt)) { error in
            XCTAssertEqual(error as? AdaptiveTrainingEngineError, .calibrationNotAtSummary(flowID))
        }
    }

    func testAnAttemptThatEndedCannotEndAgainDifferently() throws {
        let rig = makeRig()
        let flow = try pushAndSquat(rig)
        try rig.engine.commit(flow, at: endedAt)

        XCTAssertThrowsError(try rig.engine.abandon(flow, at: endedAt)) { error in
            XCTAssertEqual(error as? AdaptiveTrainingStoreError, .calibrationChangeNotAllowed(flowID))
        }
        XCTAssertEqual(try stored(rig, flowID)?.status, .committed)
        XCTAssertEqual(try rig.engine.profile().activeFamilies, [.push, .squat])
    }

    // MARK: - Later calibrations

    func testARecalibrationStartsFromTheProfileWithoutAskingEquipmentAgain() throws {
        let rig = makeRig(facts: Fixtures.seededFacts(variant: wall, dose: .reps(3)))

        let flow = try rig.engine.startCalibration(kind: .recalibration, id: flowID, at: startedAt)

        XCTAssertEqual(flow.step, .families)
        XCTAssertEqual(flow.suggestedFamilies, [.push])
        XCTAssertEqual(try stored(rig, flowID)?.kind, .recalibration)

        let first = try rig.engine.startCalibration(kind: .initial, id: Fixtures.id(51), at: startedAt)
        XCTAssertEqual(first.step, .equipment, "The first calibration always asks.")
    }
}
