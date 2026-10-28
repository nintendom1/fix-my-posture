import Foundation
import XCTest
@testable import AdaptiveTraining

final class AdaptiveSnapshotTests: XCTestCase {
    func testFamilySummariesCountAllEvidenceAndLimitRecentEvidence() throws {
        let evidence = (0..<12).map { offset -> AdaptiveEvidence in
            let effort: EffortFeedback
            switch offset % 3 {
            case 0: effort = .tooHard
            case 1: effort = .okay
            default: effort = .easy
            }
            let tracker: TrackerObservation
            switch offset {
            case 0: tracker = TrackerObservation(status: .lost, observed: .reps(0))
            case 1: tracker = TrackerObservation(status: .lowConfidence, observed: .reps(2))
            default: tracker = .notTracked
            }
            let bonus: BonusRecord? = offset % 3 == 2
                ? BonusRecord(offered: .reps(1), accepted: offset % 6 == 2,
                              completed: offset % 6 == 2 ? .reps(1) : nil)
                : nil
            let source = EvidenceSource.allCases[offset % EvidenceSource.allCases.count]
            return Fixtures.evidence(id: 20 + offset, day: offset + 1, source: source, tracker: tracker,
                                     effort: effort, bonus: bonus)
        }
        let inactiveEvidence = Fixtures.evidence(id: 50, day: 14, family: .squat,
                                                 variant: VariantID(rawValue: "squat.air_squat"), effort: nil)
        let facts = AdaptiveFacts(evidence: evidence + [inactiveEvidence], calibrations: [Fixtures.calibration()])

        let snapshot = makeSnapshot(facts)
        let push = try XCTUnwrap(snapshot.families.first { $0.family == .push })
        XCTAssertEqual(push.effort.tooHard, 4)
        XCTAssertEqual(push.effort.okay, 4)
        XCTAssertEqual(push.effort.easy, 4)
        XCTAssertEqual(push.bonus.offered, 4)
        XCTAssertEqual(push.bonus.accepted, 2)
        XCTAssertEqual(push.bonus.declined, 2)
        XCTAssertEqual(push.trackingIssues, 2)
        XCTAssertEqual(push.sources.map(\.source), EvidenceSource.allCases)
        XCTAssertEqual(push.sources.map(\.count), [3, 3, 3, 3])
        XCTAssertEqual(push.recentEvidence.count, AdaptiveSnapshot.recentEvidenceLimit)
        XCTAssertEqual(push.recentEvidence.first?.id, Fixtures.id(31))
        XCTAssertEqual(push.recentEvidence.last?.id, Fixtures.id(22))

        let inactive = try XCTUnwrap(snapshot.families.first { $0.family == .squat })
        XCTAssertFalse(inactive.isActive)
        XCTAssertNil(inactive.current)
        XCTAssertEqual(inactive.recentEvidence.first?.id, inactiveEvidence.id)
        XCTAssertEqual(inactive.recentEvidence.first?.decision, .recordOnly)
    }

    func testEvidenceDecisionLookupUsesBothIDAndFamily() throws {
        let sharedID = Fixtures.id(80)
        let activeEvidence = AdaptiveEvidence(id: sharedID, recordedAt: Fixtures.date(day: 2), source: .adaptive,
                                              family: .push, variant: Fixtures.wall, prescribed: .reps(3),
                                              confirmed: .reps(3), confirmation: .user, tracker: .notTracked,
                                              effort: .easy, completion: .completed)
        let inactiveEvidence = AdaptiveEvidence(id: sharedID, recordedAt: Fixtures.date(day: 3), source: .adaptive,
                                                family: .squat,
                                                variant: VariantID(rawValue: "squat.air_squat"),
                                                prescribed: .reps(3), confirmed: .reps(3), confirmation: .user,
                                                tracker: .notTracked, effort: .easy, completion: .completed)
        let calibration = Fixtures.calibration(
            id: 79, families: [.push, .squat],
            starts: [CalibrationStart(family: .push, start: RungDose(variant: Fixtures.wall, dose: .reps(3))),
                     CalibrationStart(family: .squat,
                                      start: RungDose(variant: VariantID(rawValue: "squat.air_squat"), dose: .reps(3)))]
        )
        let removal = SettingsFact(id: Fixtures.id(81), recordedAt: Fixtures.date(day: 1),
                                   kind: .familyRemoved, family: .squat)
        let snapshot = makeSnapshot(AdaptiveFacts(evidence: [activeEvidence, inactiveEvidence],
                                                  calibrations: [calibration], settings: [removal]))
        XCTAssertEqual(snapshot.profile.transitions.filter { $0.id == calibration.id }.count, 2)

        let pushRow = try XCTUnwrap(snapshot.families.first { $0.family == .push }?.recentEvidence.first)
        let squatRow = try XCTUnwrap(snapshot.families.first { $0.family == .squat }?.recentEvidence.first)
        XCTAssertEqual(pushRow.decision, .hold)
        XCTAssertTrue(pushRow.codes.contains(.easyOnceHold))
        XCTAssertEqual(squatRow.decision, .recordOnly)
        XCTAssertTrue(squatRow.codes.contains(.familyInactive))
    }

    func testEncodingIsStableAndRoundTripsIncludingMillisecondsAndWholeSecondDates() throws {
        let snapshot = makeSnapshot(.empty, asOf: Fixtures.anchor)
        let encoded = try AdaptiveExport.encode(snapshot)
        let encodedAgain = try AdaptiveExport.encode(snapshot)
        XCTAssertEqual(encoded, encodedAgain)
        XCTAssertEqual(try AdaptiveExport.decode(encoded), snapshot)

        let wholeSecondJSON = String(decoding: encoded, as: UTF8.self)
            .replacingOccurrences(of: ".000000000Z", with: "Z")
        XCTAssertEqual(try AdaptiveExport.decode(Data(wholeSecondJSON.utf8)), snapshot)

        let firstDate = Fixtures.date(day: 1).addingTimeInterval(0.123)
        let secondDate = firstDate.addingTimeInterval(0.300)
        let timeFacts = AdaptiveFacts(evidence: [makeEvidence(id: 92, at: firstDate),
                                                 makeEvidence(id: 91, at: secondDate)])
        let timeSnapshot = makeSnapshot(timeFacts)
        let timeDecoded = try AdaptiveExport.decode(AdaptiveExport.encode(timeSnapshot))
        let decodedEvidence = timeDecoded.facts.evidence
        XCTAssertEqual(decodedEvidence.map(\.id), [Fixtures.id(92), Fixtures.id(91)])
        guard decodedEvidence.count == 2,
              let decodedFirst = decodedEvidence.first?.recordedAt,
              let decodedSecond = decodedEvidence.dropFirst().first?.recordedAt else {
            return XCTFail("Expected both evidence dates in the decoded export.")
        }
        XCTAssertEqual(decodedFirst.timeIntervalSince1970, firstDate.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decodedSecond.timeIntervalSince1970, secondDate.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decodedSecond.timeIntervalSince(decodedFirst), 0.300, accuracy: 0.001)
    }

    func testExportDoesNotContainDeviceOrPersonalMediaIdentifiers() throws {
        let data = try AdaptiveExport.encode(makeSnapshot(.empty))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let names = allJSONNames(in: json).map { $0.lowercased() }
        for forbidden in ["device", "account", "email", "photo", "image", "frame"] {
            XCTAssertFalse(names.contains { $0.contains(forbidden) }, "Unexpected JSON name containing \(forbidden).")
        }
    }

    private func makeSnapshot(_ facts: AdaptiveFacts, asOf date: Date = Fixtures.date(day: 20)) -> AdaptiveSnapshot {
        AdaptiveReplay.snapshot(facts: facts, catalog: Fixtures.catalog,
                                builtExerciseIDs: Fixtures.allBuiltExerciseIDs, parameters: .standard,
                                calendar: Fixtures.calendar, asOf: date, appVersion: "test")
    }

    private func makeEvidence(id: Int, at date: Date) -> AdaptiveEvidence {
        AdaptiveEvidence(id: Fixtures.id(id), recordedAt: date, source: .manual, family: .push,
                         variant: Fixtures.wall, prescribed: nil, confirmed: .reps(2), confirmation: .user,
                         tracker: .notTracked, effort: .okay, completion: .completed)
    }

    private func allJSONNames(in value: Any) -> [String] {
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { name, nested in [name] + allJSONNames(in: nested) }
        }
        if let array = value as? [Any] {
            return array.flatMap(allJSONNames(in:))
        }
        return []
    }
}
