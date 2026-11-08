import Foundation
import XCTest
@testable import AdaptiveTraining

/// An export must replay exactly like the engine: lossless dates, byte-identical re-encoding, and a diff that sees
/// every transition on both sides.
final class AdaptiveExportRoundTripTests: XCTestCase {
    func testSubMillisecondFactsRoundTripExactlyAndReplayTheSameProfile() throws {
        let base = Fixtures.date(day: 1)
        // Chronological order opposes UUID order, less than a millisecond apart.
        let tooHard = evidence(id: 3, at: base.addingTimeInterval(0.0001), effort: .tooHard, prescribed: .reps(3))
        let okay = evidence(id: 2, at: base.addingTimeInterval(0.0004), effort: .okay, prescribed: .reps(2))
        // 14 days minus 0.1 ms after `okay`: not yet an absence, unless the dates lose precision.
        let returning = evidence(id: 4, at: base.addingTimeInterval(14 * 86_400 + 0.0003), effort: .easy,
                                 prescribed: .reps(2))
        let facts = AdaptiveFacts(evidence: [tooHard, okay, returning], calibrations: [Fixtures.calibration()])
        let snapshot = snapshot(facts)
        XCTAssertFalse(snapshot.profile.transitions.contains { $0.rationale.codes.contains(.returnedAfterAbsence) })

        let encoded = try AdaptiveExport.encode(snapshot)
        let decoded = try AdaptiveExport.decode(encoded)
        XCTAssertEqual(decoded.facts, facts)
        XCTAssertEqual(try AdaptiveExport.encode(decoded), encoded)
        XCTAssertEqual(AdaptiveReplay.profile(facts: decoded.facts, builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                              calendar: Fixtures.calendar), snapshot.profile)
        XCTAssertTrue(ReplayComparison.compare(decoded, parameters: nil).report.hasSuffix("No decisions change."))
    }

    func testPopulatedExportReencodesToIdenticalBytesWithoutIdentifyingKeys() throws {
        let prescription = Fixtures.prescription(id: 10, day: 1, itemID: 11)
        let tracked = AdaptiveEvidence(
            id: Fixtures.id(12), recordedAt: Fixtures.date(day: 1, hour: 13), source: .adaptive, family: .push,
            variant: Fixtures.wall, prescriptionID: Fixtures.id(10), prescriptionItemID: Fixtures.id(11),
            prescribed: .reps(3), confirmed: .reps(3), confirmation: .user, setAmounts: [.reps(3)],
            tracker: TrackerObservation(status: .lowConfidence, observed: .reps(2), rejectionReasons: ["shallow"],
                                        signals: [TrackingSignal(kind: .tempo, value: 1.25, isReliable: false)]),
            effort: .easy, midSetTooHard: true,
            bonus: BonusRecord(offered: .reps(1), accepted: true, completed: .reps(1), effort: .okay),
            completion: .completed)
        let settings = SettingsFact(id: Fixtures.id(13), recordedAt: Fixtures.date(day: 2), kind: .equipmentChanged,
                                    equipment: [.dumbbells])
        let engagement = EngagementFact(id: Fixtures.id(14), recordedAt: Fixtures.date(day: 3),
                                        kind: .sessionSkipped, family: .push)
        let facts = AdaptiveFacts(prescriptions: [prescription], evidence: [tracked],
                                  calibrations: [Fixtures.calibration()], engagement: [engagement],
                                  settings: [settings])

        let encoded = try AdaptiveExport.encode(snapshot(facts))
        let decoded = try AdaptiveExport.decode(encoded)
        XCTAssertEqual(decoded.facts, facts)
        XCTAssertEqual(try AdaptiveExport.encode(decoded), encoded)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let names = Set(jsonNames(in: json).map { $0.lowercased() })
        XCTAssertTrue(names.contains("rejectionreasons"), "The populated export should carry tracker details.")
        for forbidden in ["device", "account", "email", "photo", "image", "frame"] {
            XCTAssertFalse(names.contains { $0.contains(forbidden) }, "Unexpected JSON name containing \(forbidden).")
        }
    }

    func testExportDateIsLosslessAndAcceptsShorterFractions() throws {
        let date = Fixtures.date(day: 3).addingTimeInterval(0.000123456)
        XCTAssertEqual(ExportDate.date(ExportDate.string(date)), date)
        XCTAssertEqual(ExportDate.string(Fixtures.anchor), "2025-01-15T20:00:00.000000000Z")
        XCTAssertEqual(ExportDate.string(Fixtures.anchor, fractionDigits: 3), "2025-01-15T20:00:00.000Z")
        XCTAssertEqual(ExportDate.date("2025-01-15T20:00:00.5Z"), Fixtures.anchor.addingTimeInterval(0.5))
        XCTAssertEqual(ExportDate.date("2025-01-15T20:00:00Z"), Fixtures.anchor)
        XCTAssertEqual(ExportDate.date("1969-12-31T23:59:59Z"), Date(timeIntervalSince1970: -1))
        XCTAssertEqual(ExportDate.date("2024-02-29T00:00:00Z"), Date(timeIntervalSince1970: 1_709_164_800))
        XCTAssertNil(ExportDate.date("2025-01-15 20:00:00Z"))
        XCTAssertNil(ExportDate.date("2025-01-15T20:00:00.Z"))
        XCTAssertNil(ExportDate.date("2025-13-15T20:00:00Z"))
    }

    func testExportOnlyTransitionIsReportedAsRemoved() throws {
        let original = snapshot(AdaptiveFacts(evidence: [Fixtures.evidence(id: 20, day: 1, effort: .okay)],
                                              calibrations: [Fixtures.calibration()]))
        let extra = Transition(id: Fixtures.id(21), at: Fixtures.date(day: 2), family: .push, kind: .hold,
                               from: nil, to: RungDose(variant: Fixtures.wall, dose: .reps(3)), confidence: .medium,
                               rationale: Rationale(codes: [.okayHold], factIDs: [Fixtures.id(21)], summary: "Extra."))
        let profile = original.profile
        let withExtra = AdaptiveProfile(policyVersion: profile.policyVersion, catalogVersion: profile.catalogVersion,
                                        states: profile.states, activeFamilies: profile.activeFamilies,
                                        equipment: profile.equipment, transitions: profile.transitions + [extra])
        let exported = AdaptiveSnapshot(generatedAt: original.generatedAt, appVersion: original.appVersion,
                                        timeZone: original.timeZone, policyVersion: original.policyVersion,
                                        parameters: original.parameters, catalog: original.catalog,
                                        availability: original.availability, today: original.today,
                                        families: original.families, profile: withExtra, events: original.events,
                                        facts: original.facts)

        let report = ReplayComparison.compare(exported, parameters: nil).report

        XCTAssertTrue(report.contains("push 00000000: hold/push.wall_push_up × 3 reps → none"), report)
        XCTAssertTrue(report.contains("Total: 1 transition decisions"), report)
    }

    func testDuplicateTransitionKeysPairInOrderOnAnIdenticalReplay() {
        let twoStarts = Fixtures.calibration(starts: [
            CalibrationStart(family: .push, start: RungDose(variant: Fixtures.wall, dose: .reps(3))),
            CalibrationStart(family: .push, start: RungDose(variant: Fixtures.incline, dose: .reps(2)))
        ])
        let snapshot = snapshot(AdaptiveFacts(calibrations: [twoStarts]))
        XCTAssertEqual(snapshot.profile.transitions.filter { $0.id == twoStarts.id && $0.family == .push }.count, 2)

        XCTAssertTrue(ReplayComparison.compare(snapshot, parameters: nil).report.hasSuffix("No decisions change."))
    }

    private func snapshot(_ facts: AdaptiveFacts) -> AdaptiveSnapshot {
        AdaptiveReplay.snapshot(facts: facts, builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                calendar: Fixtures.calendar, asOf: Fixtures.date(day: 20), appVersion: "test")
    }

    private func evidence(id: Int, at date: Date, effort: EffortFeedback, prescribed: Dose) -> AdaptiveEvidence {
        AdaptiveEvidence(id: Fixtures.id(id), recordedAt: date, source: .adaptive, family: .push,
                         variant: Fixtures.wall, prescribed: prescribed, confirmed: WorkAmount(prescribed),
                         confirmation: .user, tracker: .notTracked, effort: effort, completion: .completed)
    }

    private func jsonNames(in value: Any) -> [String] {
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { name, nested in [name] + jsonNames(in: nested) }
        }
        if let array = value as? [Any] { return array.flatMap(jsonNames(in:)) }
        return []
    }
}
