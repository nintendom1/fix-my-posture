import XCTest
@testable import AdaptiveTraining

final class ReplayInvariantTests: XCTestCase {
    func testInvariant1TrackingAndConfirmedZeroNeverChangeCapacity() throws {
        let lost = Fixtures.evidence(id: 140, day: 1, confirmed: nil,
                                     tracker: TrackerObservation(status: .lost, observed: .reps(4)),
                                     effort: .easy, completion: .completed)
        let notTracked = Fixtures.evidence(id: 141, day: 2, confirmed: nil,
                                           tracker: .notTracked, effort: nil)
        let trackedOnly = Fixtures.evidence(id: 142, day: 3, confirmed: nil,
                                            tracker: TrackerObservation(status: .tracked, observed: .reps(12)),
                                            effort: nil)
        let confirmedEasy = Fixtures.evidence(id: 144, day: 4, confirmed: .reps(3), effort: .easy)
        let zero = Fixtures.evidence(id: 143, day: 5, confirmed: .reps(0), confirmation: .user, effort: .easy)
        let profile = Fixtures.profile(AdaptiveFacts(
            evidence: [lost, notTracked, trackedOnly, confirmedEasy, zero],
            calibrations: [Fixtures.calibration()]
        ))
        XCTAssertEqual(profile.state(.push)?.current.dose, .reps(3))
        XCTAssertEqual(profile.state(.push)?.lastPerformedAt, Fixtures.date(day: 5))
        XCTAssertTrue(profile.transitions.filter { [lost.id, notTracked.id, trackedOnly.id, zero.id].contains($0.id) }
            .allSatisfy { $0.kind == .recordOnly })
    }

    func testInvariant2DeclinedBonusAndProbeDoNotChangeDoseButCompletedTooHardDoes() throws {
        let calibration = Fixtures.calibration(dose: .reps(3))
        let declinedProbe = Fixtures.evidence(id: 150, day: 0, hour: 10, variant: Fixtures.wall,
                                              source: .calibration, prescribed: .reps(12), confirmed: nil,
                                              effort: nil, completion: .notAttempted,
                                              calibrationID: 1)
        let declinedBonus = Fixtures.evidence(id: 151, day: 1, confirmed: .reps(3), effort: .easy,
                                              bonus: BonusRecord(offered: .reps(1), accepted: false))
        let tooHard = Fixtures.evidence(id: 152, day: 2, prescribed: .reps(3), confirmed: .reps(3), effort: .tooHard)
        let profile = Fixtures.profile(AdaptiveFacts(
            evidence: [declinedProbe, declinedBonus, tooHard],
            calibrations: [calibration]
        ))
        XCTAssertEqual(profile.state(.push)?.current.dose, .reps(2))
        XCTAssertEqual(Fixtures.lastTransition(profile, factID: declinedBonus.id)?.kind, .hold)
        XCTAssertTrue(Fixtures.lastTransition(profile, factID: declinedBonus.id)?.rationale.codes.contains(.bonusRecordedOnly) == true)
        XCTAssertEqual(Fixtures.lastTransition(profile, factID: declinedProbe.id)?.kind, .recordOnly)
        XCTAssertEqual(Fixtures.lastTransition(profile, factID: declinedProbe.id)?.at, Fixtures.date(day: 0, hour: 12))
        XCTAssertEqual(Fixtures.lastTransition(profile, factID: tooHard.id)?.kind, .decreaseDose)
    }

    func testInvariant3EngagementAndTimePassingDoNotCreateCapacityTransitions() throws {
        let skipped = EngagementFact(id: Fixtures.id(160), recordedAt: Fixtures.date(day: 40),
                                     kind: .sessionSkipped, family: .push)
        let facts = AdaptiveFacts(
            calibrations: [Fixtures.calibration()],
            engagement: [skipped]
        )
        let profile = Fixtures.profile(facts)
        XCTAssertEqual(profile.state(.push)?.current.dose, .reps(3))
        XCTAssertEqual(profile.transitions.map(\.id), [Fixtures.id(1), skipped.id])
        XCTAssertEqual(profile.transitions.last?.kind, .recordOnly)
        XCTAssertEqual(profile.confidence(of: .push, asOf: Fixtures.date(day: 14)), .low)
    }

    func testInvariant4ShuffledFactsAndRepeatedReplayEncodeIdentically() throws {
        let calibration = Fixtures.calibration(id: 1, dose: .reps(3))
        let first = Fixtures.evidence(id: 170, day: 1)
        let second = Fixtures.evidence(id: 171, day: 2)
        let setting = SettingsFact(id: Fixtures.id(172), recordedAt: Fixtures.date(day: 1),
                                   kind: .equipmentChanged, equipment: [])
        let engagement = EngagementFact(id: Fixtures.id(173), recordedAt: Fixtures.date(day: 2),
                                        kind: .sessionSkipped, family: .push)
        let prescription = Fixtures.prescription(id: 174, day: 0, itemID: 175)
        let leftFacts = AdaptiveFacts(
            prescriptions: [prescription],
            evidence: [first, second],
            calibrations: [calibration],
            engagement: [engagement],
            settings: [setting]
        )
        let rightFacts = AdaptiveFacts(
            prescriptions: [prescription],
            evidence: [second, first],
            calibrations: [calibration],
            engagement: [engagement],
            settings: [setting]
        )
        let left = Fixtures.profile(leftFacts)
        let replayed = Fixtures.profile(leftFacts)
        let right = Fixtures.profile(rightFacts)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(left), try encoder.encode(replayed))
        XCTAssertEqual(try encoder.encode(left), try encoder.encode(right))
    }

    func testInvariant7UncommittedCalibrationsAndTheirProbesHaveNoEffect() throws {
        let abandoned = Fixtures.calibration(id: 180, dose: .reps(9), status: .abandoned)
        let inProgress = Fixtures.calibration(id: 181, family: .squat,
                                              variant: VariantID(rawValue: "squat.air_squat"), dose: .reps(8),
                                              status: .inProgress)
        let abandonedProbe = Fixtures.evidence(id: 182, day: 0, hour: 9, variant: Fixtures.wall,
                                               source: .calibration, prescribed: .reps(9), confirmed: .reps(9),
                                               effort: .easy, calibrationID: 180)
        let activeProbe = Fixtures.evidence(id: 183, day: 0, hour: 9, family: .squat,
                                            variant: VariantID(rawValue: "squat.air_squat"), source: .calibration,
                                            prescribed: .reps(8), confirmed: .reps(8), effort: .easy,
                                            calibrationID: 181)
        let profile = Fixtures.profile(AdaptiveFacts(
            evidence: [abandonedProbe, activeProbe],
            calibrations: [abandoned, inProgress]
        ))
        XCTAssertTrue(profile.states.isEmpty)
        XCTAssertTrue(profile.activeFamilies.isEmpty)
        XCTAssertEqual(profile.transitions.count, 4)
        XCTAssertTrue(profile.transitions.allSatisfy { $0.kind == .recordOnly })
        XCTAssertTrue(profile.transitions.allSatisfy { $0.rationale.codes.contains(.calibrationNotCommitted) })
    }

    func testInvariant7CommittedRecalibrationResetsCurrentAndKeepsEvidenceAndComfort() throws {
        let oldRating = Fixtures.evidence(id: 190, day: 1, prescribed: .reps(4), confirmed: .reps(4), effort: .okay)
        let recalibration = Fixtures.calibration(id: 191, day: 2, variant: Fixtures.wall, dose: .reps(8),
                                                 kind: .recalibration)
        let facts = AdaptiveFacts(
            evidence: [oldRating],
            calibrations: [Fixtures.calibration(), recalibration]
        )
        let profile = Fixtures.profile(facts)
        let state = try XCTUnwrap(profile.state(.push))
        XCTAssertEqual(state.current.dose, .reps(8))
        XCTAssertEqual(state.comfortableDose(on: Fixtures.wall)?.dose, .reps(4))
        XCTAssertTrue(profile.transitions.contains { $0.id == oldRating.id })
        XCTAssertTrue(facts.evidence.contains { $0.id == oldRating.id })
    }

    func testReturnAfterAbsenceHoldsOnceAndStartsANewStreak() throws {
        let first = Fixtures.evidence(id: 200, day: 1)
        let returned = Fixtures.evidence(id: 201, day: 15)
        let next = Fixtures.evidence(id: 202, day: 16)
        let profile = Fixtures.profile(AdaptiveFacts(
            evidence: [first, returned, next],
            calibrations: [Fixtures.calibration()]
        ))
        XCTAssertEqual(profile.state(.push)?.current.dose, .reps(3))
        XCTAssertEqual(profile.state(.push)?.easyStreak, 1)
        XCTAssertTrue(Fixtures.lastTransition(profile, factID: returned.id)?.rationale.codes.contains(.returnedAfterAbsence) == true)
        XCTAssertEqual(Fixtures.lastTransition(profile, factID: returned.id)?.confidence, .medium)
        XCTAssertFalse(Fixtures.lastTransition(profile, factID: next.id)?.rationale.codes.contains(.returnedAfterAbsence) ?? false)
    }

    func testEquipmentChangeFamilyRemovalAndAddFamilyCalibrationUpdateAvailability() throws {
        let rowVariant = VariantID(rawValue: "row.dumbbell_row")
        let rowFloor = VariantID(rawValue: "row.scapular_squeeze.seated")
        let initial = Fixtures.calibration(id: 210, family: .row, variant: rowVariant, dose: .reps(6),
                                            equipment: [.dumbbells])
        let noDumbbells = SettingsFact(id: Fixtures.id(211), recordedAt: Fixtures.date(day: 1),
                                       kind: .equipmentChanged, equipment: [])
        let removed = SettingsFact(id: Fixtures.id(212), recordedAt: Fixtures.date(day: 2),
                                   kind: .familyRemoved, family: .row)
        let addFamily = Fixtures.calibration(id: 213, day: 3, family: .row, variant: rowFloor, dose: .reps(2),
                                             kind: .addFamily)
        let profile = Fixtures.profile(AdaptiveFacts(
            calibrations: [initial, addFamily],
            settings: [noDumbbells, removed]
        ))
        XCTAssertEqual(profile.state(.row)?.current,
                       RungDose(variant: rowFloor, dose: .reps(2)))
        XCTAssertEqual(profile.activeFamilies, [.row])
        XCTAssertEqual(profile.equipment, [])
        XCTAssertTrue(Fixtures.lastTransition(profile, factID: noDumbbells.id)?.rationale.codes.contains(.rungUnavailable) == true)
        XCTAssertEqual(Fixtures.lastTransition(profile, factID: removed.id)?.kind, .deactivate)
        XCTAssertEqual(Fixtures.lastTransition(profile, factID: addFamily.id)?.kind, .start)
    }
}
