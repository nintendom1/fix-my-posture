import XCTest
@testable import AdaptiveTraining

/// Boundaries and cross-rule cases for policy V1: stale prescriptions, probes committed later, absence before a
/// harder sample, and the exact 14-, 28-, and 7-day thresholds.
final class PolicyV1EdgeCaseTests: XCTestCase {
    func testTooHardAboveCurrentIsRecordedWithoutMovingCapacity() throws {
        let higherDose = Fixtures.evidence(id: 2, day: 1, prescribed: .reps(8), confirmed: .reps(8), effort: .tooHard)
        let doseProfile = Fixtures.profile(AdaptiveFacts(evidence: [higherDose],
                                                         calibrations: [Fixtures.calibration(dose: .reps(3))]))
        XCTAssertEqual(doseProfile.state(.push)?.current, RungDose(variant: Fixtures.wall, dose: .reps(3)))
        let doseTransition = try XCTUnwrap(Fixtures.lastTransition(doseProfile, factID: higherDose.id))
        XCTAssertEqual(doseTransition.kind, .recordOnly)
        XCTAssertTrue(doseTransition.rationale.codes.contains(.manualOtherRungRecorded))

        let higherRung = Fixtures.evidence(id: 3, day: 1, variant: Fixtures.incline, prescribed: .reps(3),
                                           confirmed: .reps(3), effort: .tooHard)
        let rungProfile = Fixtures.profile(AdaptiveFacts(evidence: [higherRung],
                                                         calibrations: [Fixtures.calibration(dose: .reps(3))]))
        XCTAssertEqual(rungProfile.state(.push)?.current, RungDose(variant: Fixtures.wall, dose: .reps(3)))
        XCTAssertEqual(Fixtures.lastTransition(rungProfile, factID: higherRung.id)?.kind, .recordOnly)
        XCTAssertFalse(AdaptiveReplay.events(facts: AdaptiveFacts(evidence: [higherRung],
                                                                  calibrations: [Fixtures.calibration(dose: .reps(3))]),
                                             profile: rungProfile).contains { $0.kind == .regressed })
    }

    func testHarderSampleAfterAbsenceHoldsAndJustBeforeIsAccepted() throws {
        let performed = Fixtures.evidence(id: 2, day: 1, prescribed: .reps(12), confirmed: .reps(12), effort: .okay)
        let prescription = Fixtures.prescription(id: 3, day: 15, itemID: 4, variant: Fixtures.incline,
                                                 dose: .reps(1), role: .harderSample)
        func sample(hour: Int) -> AdaptiveEvidence {
            Fixtures.evidence(id: 5, day: 15, hour: hour, variant: Fixtures.incline, prescribed: .reps(1),
                              confirmed: .reps(1), effort: .okay, itemID: 4, prescriptionID: 3)
        }

        let atThreshold = AdaptiveFacts(prescriptions: [prescription], evidence: [performed, sample(hour: 12)],
                                        calibrations: [Fixtures.calibration(dose: .reps(12))])
        let held = Fixtures.profile(atThreshold)
        let heldState = try XCTUnwrap(held.state(.push))
        XCTAssertEqual(heldState.current, RungDose(variant: Fixtures.wall, dose: .reps(12)))
        XCTAssertEqual(heldState.confidence, .medium)
        XCTAssertEqual(heldState.easyStreak, 0)
        let heldTransition = try XCTUnwrap(Fixtures.lastTransition(held, factID: Fixtures.id(5)))
        XCTAssertEqual(heldTransition.kind, .hold)
        XCTAssertTrue(heldTransition.rationale.codes.contains(.returnedAfterAbsence))
        XCTAssertTrue(AdaptiveReplay.events(facts: atThreshold, profile: held)
            .contains { $0.kind == .returnedAfterAbsence && $0.factID == Fixtures.id(5) })

        let justBefore = Fixtures.profile(AdaptiveFacts(prescriptions: [prescription],
                                                        evidence: [performed, sample(hour: 11)],
                                                        calibrations: [Fixtures.calibration(dose: .reps(12))]))
        XCTAssertEqual(justBefore.state(.push)?.current, RungDose(variant: Fixtures.incline, dose: .reps(1)))
    }

    func testHarderSampleTooHardClearsTheEasyStreak() {
        let first = Fixtures.evidence(id: 2, day: 1, prescribed: .reps(12), confirmed: .reps(12))
        let second = Fixtures.evidence(id: 3, day: 2, prescribed: .reps(12), confirmed: .reps(12))
        let third = Fixtures.evidence(id: 4, day: 3, hour: 10, prescribed: .reps(12), confirmed: .reps(12))
        let prescription = Fixtures.prescription(id: 5, day: 3, itemID: 6, variant: Fixtures.incline,
                                                 dose: .reps(1), role: .harderSample)
        let tooHard = Fixtures.evidence(id: 7, day: 3, variant: Fixtures.incline, prescribed: .reps(1),
                                        confirmed: .reps(0), effort: .tooHard, itemID: 6, prescriptionID: 5)
        let profile = Fixtures.profile(AdaptiveFacts(prescriptions: [prescription],
                                                     evidence: [first, second, third, tooHard],
                                                     calibrations: [Fixtures.calibration(dose: .reps(12))]))
        XCTAssertEqual(profile.state(.push)?.easyStreak, 0)
        XCTAssertNil(profile.state(.push)?.lastEasyAt)
    }

    func testTooHardProbePurgesComfortFromTheSameCalibration() {
        let okay = Fixtures.evidence(id: 2, day: 1, source: .calibration, prescribed: .reps(7), confirmed: .reps(7),
                                     effort: .okay, calibrationID: 1)
        let tooHard = Fixtures.evidence(id: 3, day: 2, source: .calibration, prescribed: .reps(7),
                                        confirmed: .reps(7), effort: .tooHard, calibrationID: 1)
        let later = Fixtures.evidence(id: 4, day: 4, prescribed: .reps(8), confirmed: .reps(8), effort: .tooHard)
        let profile = Fixtures.profile(AdaptiveFacts(evidence: [okay, tooHard, later],
                                                     calibrations: [Fixtures.calibration(day: 3, dose: .reps(8))]))
        XCTAssertEqual(profile.state(.push)?.current.dose, .reps(6))
        XCTAssertNil(profile.state(.push)?.comfortableDose(on: Fixtures.wall))
    }

    func testRecalibrationTooHardProbePurgesEarlierComfort() {
        let comfortable = Fixtures.evidence(id: 2, day: 1, prescribed: .reps(6), confirmed: .reps(6), effort: .okay)
        let tooHard = Fixtures.evidence(id: 4, day: 2, source: .recalibration, prescribed: .reps(6), confirmed: nil,
                                        effort: .tooHard, calibrationID: 3)
        let profile = Fixtures.profile(AdaptiveFacts(
            evidence: [comfortable, tooHard],
            calibrations: [Fixtures.calibration(dose: .reps(8)),
                           Fixtures.calibration(id: 3, day: 3, dose: .reps(8), kind: .recalibration)]
        ))
        XCTAssertNil(profile.state(.push)?.comfortableDose(on: Fixtures.wall))
    }

    func testOlderProbeCommittedLaterKeepsNewerComfortAndPerformanceTime() throws {
        let probe = Fixtures.evidence(id: 3, day: 1, source: .recalibration, prescribed: .reps(7),
                                      confirmed: .reps(7), effort: .okay, calibrationID: 2)
        let fresh = Fixtures.evidence(id: 4, day: 3, prescribed: .reps(4), confirmed: .reps(4), effort: .okay)
        let profile = Fixtures.profile(AdaptiveFacts(
            evidence: [probe, fresh],
            calibrations: [Fixtures.calibration(dose: .reps(8)),
                           Fixtures.calibration(id: 2, day: 5, dose: .reps(8), kind: .recalibration)]
        ))
        let state = try XCTUnwrap(profile.state(.push))
        XCTAssertEqual(state.comfortableDose(on: Fixtures.wall)?.dose, .reps(4))
        XCTAssertEqual(state.comfortableDose(on: Fixtures.wall)?.ratedAt, fresh.recordedAt)
        XCTAssertEqual(state.lastPerformedAt, fresh.recordedAt)
    }

    func testManualTooHardWithoutPositiveWorkUsesThePerformedRungMinimum() {
        let zero = Fixtures.evidence(id: 2, day: 1, variant: Fixtures.shallowWall, source: .manual, prescribed: nil,
                                     confirmed: .reps(0), setAmounts: [.reps(0)], effort: .tooHard)
        let none = Fixtures.evidence(id: 3, day: 1, variant: Fixtures.shallowWall, source: .manual, prescribed: nil,
                                     confirmed: nil, effort: .tooHard)
        for evidence in [zero, none] {
            let profile = Fixtures.profile(AdaptiveFacts(evidence: [evidence],
                                                         calibrations: [Fixtures.calibration(dose: .reps(8))]))
            XCTAssertEqual(profile.state(.push)?.current, RungDose(variant: Fixtures.shallowWall, dose: .reps(1)))
        }
    }

    func testManualHarderRungNeverMovesPastThePerformedRung() {
        // Incline isn't built, so the next available rung above wall is the push-up, above the performed rung.
        let built = Fixtures.allBuiltExerciseIDs.subtracting(["incline_push_up"])
        let manual = Fixtures.evidence(id: 2, day: 1, variant: Fixtures.incline, source: .manual, prescribed: nil,
                                       confirmed: .reps(3), setAmounts: [.reps(3)], effort: .easy)
        let profile = Fixtures.profile(AdaptiveFacts(evidence: [manual], calibrations: [Fixtures.calibration()]),
                                       builtExerciseIDs: built)
        XCTAssertEqual(profile.state(.push)?.current, RungDose(variant: Fixtures.wall, dose: .reps(3)))
        XCTAssertEqual(Fixtures.lastTransition(profile, factID: manual.id)?.kind, .recordOnly)
    }

    func testManualOkayOnTheCurrentRungHoldsAndBreaksTheStreak() throws {
        let easy = Fixtures.evidence(id: 2, day: 1, source: .manual, prescribed: nil, confirmed: .reps(3),
                                     setAmounts: [.reps(3)], effort: .easy)
        let okay = Fixtures.evidence(id: 3, day: 2, source: .manual, prescribed: nil, confirmed: .reps(3),
                                     setAmounts: [.reps(3)], effort: .okay)
        let profile = Fixtures.profile(AdaptiveFacts(evidence: [easy, okay], calibrations: [Fixtures.calibration()]))
        let state = try XCTUnwrap(profile.state(.push))
        XCTAssertEqual(state.current.dose, .reps(3))
        XCTAssertEqual(state.easyStreak, 0)
        XCTAssertTrue(Fixtures.lastTransition(profile, factID: okay.id)?.rationale.codes.contains(.okayHold) == true)
    }

    func testEveryEarlyRecordOnlyGateKeepsTheBonusCode() {
        let bonus = BonusRecord(offered: .reps(1), accepted: false)
        let cases: [(String, AdaptiveEvidence)] = [
            ("not attempted", Fixtures.evidence(id: 2, day: 1, confirmed: nil, effort: nil, completion: .notAttempted,
                                                bonus: bonus)),
            ("unrated", Fixtures.evidence(id: 3, day: 1, effort: nil, bonus: bonus)),
            ("unconfirmed", Fixtures.evidence(id: 4, day: 1, confirmed: nil, effort: .easy, bonus: bonus)),
            ("confirmed zero", Fixtures.evidence(id: 5, day: 1, confirmed: .reps(0), effort: .easy, bonus: bonus))
        ]
        for (name, evidence) in cases {
            let profile = Fixtures.profile(AdaptiveFacts(evidence: [evidence], calibrations: [Fixtures.calibration()]))
            let transition = Fixtures.lastTransition(profile, factID: evidence.id)
            XCTAssertEqual(transition?.kind, .recordOnly, name)
            XCTAssertTrue(transition?.rationale.codes.contains(.bonusRecordedOnly) == true, name)
            XCTAssertEqual(profile.state(.push)?.current.dose, .reps(3), name)
        }
    }

    func testRemovedFamilyDoesNotNeedAnotherCalibration() {
        XCTAssertTrue(Fixtures.profile(.empty).needsCalibration)
        let removed = SettingsFact(id: Fixtures.id(2), recordedAt: Fixtures.date(day: 1), kind: .familyRemoved,
                                   family: .push)
        let facts = AdaptiveFacts(calibrations: [Fixtures.calibration()], settings: [removed])
        let profile = Fixtures.profile(facts)
        XCTAssertFalse(profile.needsCalibration)
        XCTAssertEqual(AdaptiveReplay.todaySession(profile: profile, facts: facts,
                                                   builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                                   calendar: Fixtures.calendar, asOf: Fixtures.date(day: 2)),
                       .nothingOffered)
    }

    func testAbsenceStartsAtExactlyFourteenDays() {
        let first = Fixtures.evidence(id: 2, day: 1)
        func profile(hour: Int) -> AdaptiveProfile {
            Fixtures.profile(AdaptiveFacts(evidence: [first, Fixtures.evidence(id: 3, day: 15, hour: hour)],
                                           calibrations: [Fixtures.calibration()]))
        }
        let before = profile(hour: 11)
        XCTAssertEqual(before.state(.push)?.current.dose, .reps(4))
        XCTAssertFalse(Fixtures.lastTransition(before, factID: Fixtures.id(3))?.rationale.codes
            .contains(.returnedAfterAbsence) ?? true)

        let at = profile(hour: 12)
        XCTAssertEqual(at.state(.push)?.current.dose, .reps(3))
        XCTAssertTrue(Fixtures.lastTransition(at, factID: Fixtures.id(3))?.rationale.codes
            .contains(.returnedAfterAbsence) == true)
    }

    func testEasyStreakIncludesExactlyTwentyEightDays() {
        // Unrated work in between keeps the family from counting as absent.
        let first = Fixtures.evidence(id: 2, day: 1)
        let keepUp = [Fixtures.evidence(id: 3, day: 10, effort: nil), Fixtures.evidence(id: 4, day: 20, effort: nil)]
        func profile(hour: Int) -> AdaptiveProfile {
            Fixtures.profile(AdaptiveFacts(evidence: [first] + keepUp + [Fixtures.evidence(id: 5, day: 29, hour: hour)],
                                           calibrations: [Fixtures.calibration()]))
        }
        XCTAssertEqual(profile(hour: 12).state(.push)?.current.dose, .reps(4))

        let stale = profile(hour: 13)
        XCTAssertEqual(stale.state(.push)?.current.dose, .reps(3))
        XCTAssertEqual(stale.state(.push)?.easyStreak, 1)
        XCTAssertTrue(Fixtures.lastTransition(stale, factID: Fixtures.id(5))?.rationale.codes
            .contains(.staleHistoryIgnored) == true)
    }

    func testHarderSampleCooldownEndsAtExactlySevenDays() {
        let streak = [Fixtures.evidence(id: 2, day: 1, prescribed: .reps(12), confirmed: .reps(12)),
                      Fixtures.evidence(id: 3, day: 2, prescribed: .reps(12), confirmed: .reps(12))]
        let prescription = Fixtures.prescription(id: 4, day: 3, itemID: 5, variant: Fixtures.incline,
                                                 dose: .reps(1), role: .harderSample)
        let tooHard = Fixtures.evidence(id: 6, day: 3, variant: Fixtures.incline, prescribed: .reps(1),
                                        confirmed: .reps(1), effort: .tooHard, itemID: 5, prescriptionID: 4)
        let easyAgain = Fixtures.evidence(id: 7, day: 9, prescribed: .reps(12), confirmed: .reps(12))
        func profile(hour: Int) -> AdaptiveProfile {
            let last = Fixtures.evidence(id: 8, day: 10, hour: hour, prescribed: .reps(12), confirmed: .reps(12))
            return Fixtures.profile(AdaptiveFacts(prescriptions: [prescription],
                                                  evidence: streak + [tooHard, easyAgain, last],
                                                  calibrations: [Fixtures.calibration(dose: .reps(12))]))
        }
        let blocked = profile(hour: 11)
        XCTAssertEqual(Fixtures.lastTransition(blocked, factID: Fixtures.id(8))?.kind, .hold)
        XCTAssertFalse(blocked.state(.push)?.harderSampleDue ?? true)

        let expired = profile(hour: 12)
        XCTAssertEqual(Fixtures.lastTransition(expired, factID: Fixtures.id(8))?.kind, .offerHarderSample)
        XCTAssertTrue(expired.state(.push)?.harderSampleDue == true)
    }
}
