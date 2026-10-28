import XCTest
@testable import AdaptiveTraining

final class PolicyV1Tests: XCTestCase {
    func testTooHardUsesRecentComfortableDoseBeforeReducing() throws {
        let rating = Fixtures.evidence(id: 10, day: 1, prescribed: .reps(4), confirmed: .reps(4), effort: .okay)
        let tooHard = Fixtures.evidence(id: 11, day: 2, prescribed: .reps(6), confirmed: .reps(6), effort: .tooHard)
        let profile = Fixtures.profile(AdaptiveFacts(
            evidence: [rating, tooHard],
            calibrations: [Fixtures.calibration(dose: .reps(6))]
        ))
        let state = try XCTUnwrap(profile.state(.push))
        XCTAssertEqual(state.current, RungDose(variant: Fixtures.wall, dose: .reps(4)))
        XCTAssertTrue(Fixtures.lastTransition(profile, factID: tooHard.id)?.rationale.codes.contains(.tooHardBackToComfortable) == true)
    }

    func testTooHardReductionCoversRepAndSecondDoses() throws {
        let cases: [(MovementFamilyID, VariantID, Dose, Dose)] = [
            (.push, Fixtures.wall, .reps(4), .reps(3)),
            (.push, Fixtures.wall, .reps(8), .reps(6)),
            (.glute, Fixtures.gluteHold, .seconds(20), .seconds(15))
        ]
        for (index, value) in cases.enumerated() {
            let evidence = Fixtures.evidence(id: 20 + index, day: 1, family: value.0, variant: value.1,
                                             prescribed: value.2, confirmed: WorkAmount(value.2), effort: .tooHard)
            let calibration = Fixtures.calibration(id: 2 + index, family: value.0, variant: value.1, dose: value.2)
            let profile = Fixtures.profile(AdaptiveFacts(
                evidence: [evidence],
                calibrations: [calibration]
            ))
            XCTAssertEqual(profile.state(value.0)?.current, RungDose(variant: value.1, dose: value.3))
            XCTAssertTrue(Fixtures.lastTransition(profile, factID: evidence.id)?.rationale.codes.contains(.tooHardReducedDose) == true)
        }
    }

    func testTooHardAtMinimumUsesEasierRungAndAtFloorHolds() throws {
        let atWall = Fixtures.evidence(id: 31, day: 1, variant: Fixtures.wall, prescribed: .reps(1),
                                       confirmed: .reps(1), effort: .tooHard)
        let wallProfile = Fixtures.profile(AdaptiveFacts(
            evidence: [atWall],
            calibrations: [Fixtures.calibration(dose: .reps(1))]
        ))
        XCTAssertEqual(wallProfile.state(.push)?.current,
                       RungDose(variant: Fixtures.shallowWall, dose: .reps(1)))
        XCTAssertEqual(Fixtures.lastTransition(wallProfile, factID: atWall.id)?.kind, .easierVariant)

        let atFloor = Fixtures.evidence(id: 32, day: 1, variant: Fixtures.shallowWall, prescribed: .reps(1),
                                        confirmed: .reps(1), effort: .tooHard)
        let floorProfile = Fixtures.profile(AdaptiveFacts(
            evidence: [atFloor],
            calibrations: [Fixtures.calibration(variant: Fixtures.shallowWall,
                                                                                              dose: .reps(1))]
        ))
        XCTAssertEqual(floorProfile.state(.push)?.current,
                       RungDose(variant: Fixtures.shallowWall, dose: .reps(1)))
        XCTAssertEqual(Fixtures.lastTransition(floorProfile, factID: atFloor.id)?.kind, .hold)
        XCTAssertEqual(floorProfile.state(.push)?.confidence, .low)
    }

    func testOkayHoldsAndEasyNeedsDifferentDaysToIncreaseOneDoseStep() throws {
        let okay = Fixtures.evidence(id: 40, day: 1, effort: .okay)
        let okayProfile = Fixtures.profile(AdaptiveFacts(
            evidence: [okay],
            calibrations: [Fixtures.calibration()]
        ))
        XCTAssertEqual(okayProfile.state(.push)?.current.dose, .reps(3))
        XCTAssertEqual(Fixtures.lastTransition(okayProfile, factID: okay.id)?.rationale.codes.first, .okayHold)

        let first = Fixtures.evidence(id: 41, day: 1)
        let onceProfile = Fixtures.profile(AdaptiveFacts(
            evidence: [first],
            calibrations: [Fixtures.calibration()]
        ))
        XCTAssertEqual(onceProfile.state(.push)?.current.dose, .reps(3))
        XCTAssertEqual(onceProfile.state(.push)?.easyStreak, 1)

        let second = Fixtures.evidence(id: 42, day: 2)
        let profile = Fixtures.profile(AdaptiveFacts(
            evidence: [first, second],
            calibrations: [Fixtures.calibration()]
        ))
        XCTAssertEqual(profile.state(.push)?.current.dose, .reps(4))
        XCTAssertEqual(Fixtures.lastTransition(profile, factID: second.id)?.rationale.factIDs, [first.id, second.id])
    }

    func testSameDayEasyDoesNotIncreaseAndOkayBreaksTheStreak() throws {
        let first = Fixtures.evidence(id: 50, day: 1, hour: 9)
        let sameDay = Fixtures.evidence(id: 51, day: 1, hour: 16)
        let sameDayProfile = Fixtures.profile(AdaptiveFacts(
            evidence: [first, sameDay],
            calibrations: [Fixtures.calibration()]
        ))
        XCTAssertEqual(sameDayProfile.state(.push)?.current.dose, .reps(3))
        XCTAssertEqual(sameDayProfile.state(.push)?.easyStreak, 1)
        XCTAssertFalse(Fixtures.lastTransition(sameDayProfile, factID: sameDay.id)?.rationale.codes.contains(.easyStreakIncrease) ?? false)

        let okay = Fixtures.evidence(id: 52, day: 2, effort: .okay)
        let last = Fixtures.evidence(id: 53, day: 3)
        let brokenProfile = Fixtures.profile(AdaptiveFacts(
            evidence: [first, okay, last],
            calibrations: [Fixtures.calibration()]
        ))
        XCTAssertEqual(brokenProfile.state(.push)?.current.dose, .reps(3))
        XCTAssertEqual(brokenProfile.state(.push)?.easyStreak, 1)
    }

    func testStaleEasyHistoryStartsANewStreak() throws {
        let first = Fixtures.evidence(id: 60, day: 1)
        let unrated = Fixtures.evidence(id: 62, day: 20, confirmed: nil, effort: nil)
        let stale = Fixtures.evidence(id: 61, day: 30)
        let profile = Fixtures.profile(AdaptiveFacts(
            evidence: [first, unrated, stale],
            calibrations: [Fixtures.calibration()]
        ))
        XCTAssertEqual(profile.state(.push)?.current.dose, .reps(3))
        XCTAssertEqual(profile.state(.push)?.easyStreak, 1)
        XCTAssertTrue(Fixtures.lastTransition(profile, factID: stale.id)?.rationale.codes.contains(.staleHistoryIgnored) == true)
    }

    func testTopOfRangeOffersHarderSampleAfterTwoEasyDays() throws {
        let first = Fixtures.evidence(id: 70, day: 1, prescribed: .reps(12), confirmed: .reps(12))
        let second = Fixtures.evidence(id: 71, day: 2, prescribed: .reps(12), confirmed: .reps(12))
        let profile = Fixtures.profile(AdaptiveFacts(
            evidence: [first, second],
            calibrations: [Fixtures.calibration(dose: .reps(12))]
        ))
        XCTAssertTrue(profile.state(.push)?.harderSampleDue == true)
        XCTAssertEqual(Fixtures.lastTransition(profile, factID: second.id)?.kind, .offerHarderSample)
    }

    func testHarderSampleAcceptanceMovesToItsMinimumDose() throws {
        let first = Fixtures.evidence(id: 80, day: 1, prescribed: .reps(12), confirmed: .reps(12))
        let second = Fixtures.evidence(id: 81, day: 2, prescribed: .reps(12), confirmed: .reps(12))
        let prescription = Fixtures.prescription(id: 82, day: 2, itemID: 83, variant: Fixtures.incline,
                                                 dose: .reps(1), role: .harderSample)
        let accepted = Fixtures.evidence(id: 84, day: 3, variant: Fixtures.incline, prescribed: .reps(1),
                                         confirmed: .reps(1), effort: .okay, itemID: 83, prescriptionID: 82)
        let profile = Fixtures.profile(AdaptiveFacts(
            prescriptions: [prescription],
            evidence: [first, second, accepted],
            calibrations: [Fixtures.calibration(dose: .reps(12))]
        ))
        XCTAssertEqual(profile.state(.push)?.current,
                       RungDose(variant: Fixtures.incline, dose: .reps(1)))
        XCTAssertEqual(Fixtures.lastTransition(profile, factID: accepted.id)?.rationale.codes.first,
                       .harderSampleAccepted)
    }

    func testHarderSampleCooldownDeclineAndLaterOffer() throws {
        let first = Fixtures.evidence(id: 90, day: 1, prescribed: .reps(12), confirmed: .reps(12))
        let second = Fixtures.evidence(id: 91, day: 2, prescribed: .reps(12), confirmed: .reps(12))
        let samplePrescription = Fixtures.prescription(id: 92, day: 2, itemID: 93, variant: Fixtures.incline,
                                                       dose: .reps(1), role: .harderSample)
        let sampleTooHard = Fixtures.evidence(id: 94, day: 3, variant: Fixtures.incline, prescribed: .reps(1),
                                              confirmed: .reps(1), effort: .tooHard,
                                              itemID: 93, prescriptionID: 92)
        let early = Fixtures.evidence(id: 95, day: 9, prescribed: .reps(12), confirmed: .reps(12))
        let late = Fixtures.evidence(id: 96, day: 11, prescribed: .reps(12), confirmed: .reps(12))
        let facts = AdaptiveFacts(
            prescriptions: [samplePrescription],
            evidence: [first, second, sampleTooHard, early, late],
            calibrations: [Fixtures.calibration(dose: .reps(12))]
        )
        let profile = Fixtures.profile(facts)
        XCTAssertEqual(profile.state(.push)?.harderSampleBlockedUntil, Fixtures.date(day: 10))
        XCTAssertTrue(profile.state(.push)?.harderSampleDue == true)

        let beforeExpiry = AdaptiveReplay.todaySession(profile: profile, facts: facts, builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                                       calendar: Fixtures.calendar, asOf: Fixtures.date(day: 9))
        if case .ready(let session) = beforeExpiry {
            XCTAssertNil(session.harderSample)
        } else {
            XCTFail("Expected the rotation to offer a main item during cooldown.")
        }
        let afterExpiry = AdaptiveReplay.todaySession(profile: profile, facts: facts, builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                                      calendar: Fixtures.calendar, asOf: Fixtures.date(day: 11))
        if case .ready(let session) = afterExpiry {
            XCTAssertEqual(session.harderSample?.variant, Fixtures.incline)
        } else {
            XCTFail("Expected a harder sample after the cooldown and another Easy streak.")
        }

        let declined = Fixtures.evidence(id: 97, day: 12, variant: Fixtures.incline, prescribed: .reps(1),
                                         confirmed: nil, effort: nil, completion: .notAttempted,
                                         itemID: 93, prescriptionID: 92)
        let declinedProfile = Fixtures.profile(AdaptiveFacts(
            prescriptions: [samplePrescription],
            evidence: [first, second, declined],
            calibrations: [Fixtures.calibration(dose: .reps(12))]
        ))
        XCTAssertTrue(declinedProfile.state(.push)?.harderSampleDue == true)
        XCTAssertTrue(Fixtures.lastTransition(declinedProfile, factID: declined.id)?.rationale.codes.contains(.harderSampleDeclined) == true)
    }

    func testStoppedEarlyOkayOrEasyHoldsAndBreaksStreak() throws {
        let first = Fixtures.evidence(id: 100, day: 1)
        let stopped = Fixtures.evidence(id: 101, day: 2, prescribed: .reps(3), confirmed: .reps(2),
                                        completion: .stoppedEarly)
        let profile = Fixtures.profile(AdaptiveFacts(
            evidence: [first, stopped],
            calibrations: [Fixtures.calibration()]
        ))
        XCTAssertEqual(profile.state(.push)?.current.dose, .reps(3))
        XCTAssertEqual(profile.state(.push)?.easyStreak, 0)
        XCTAssertTrue(Fixtures.lastTransition(profile, factID: stopped.id)?.rationale.codes.contains(.stoppedEarlyHold) == true)
    }

    func testManualHarderRungMovesExactlyOneRung() throws {
        let manual = Fixtures.evidence(id: 110, day: 1, variant: Fixtures.pushUp, source: .manual,
                                       prescribed: nil, confirmed: .reps(2), setAmounts: [.reps(2)], effort: .easy)
        let profile = Fixtures.profile(AdaptiveFacts(
            evidence: [manual],
            calibrations: [Fixtures.calibration(variant: Fixtures.shallowWall)]
        ))
        XCTAssertEqual(profile.state(.push)?.current,
                       RungDose(variant: Fixtures.wall, dose: .reps(2)))
        XCTAssertTrue(Fixtures.lastTransition(profile, factID: manual.id)?.rationale.codes.contains(.manualHarderRungUp) == true)
    }

    func testManualSameRungEasyCountsAtOrAboveCurrentAndBelowCurrentOkayIsRecordOnly() throws {
        let first = Fixtures.evidence(id: 120, day: 1, source: .manual, prescribed: nil,
                                      confirmed: .reps(4), setAmounts: [.reps(4)], effort: .easy)
        let second = Fixtures.evidence(id: 121, day: 2, source: .manual, prescribed: nil,
                                       confirmed: .reps(4), setAmounts: [.reps(4)], effort: .easy)
        let profile = Fixtures.profile(AdaptiveFacts(
            evidence: [first, second],
            calibrations: [Fixtures.calibration()]
        ))
        XCTAssertEqual(profile.state(.push)?.current.dose, .reps(4))

        let below = Fixtures.evidence(id: 122, day: 1, source: .manual, prescribed: nil,
                                      confirmed: .reps(2), setAmounts: [.reps(2)], effort: .okay)
        let belowProfile = Fixtures.profile(AdaptiveFacts(
            evidence: [below],
            calibrations: [Fixtures.calibration()]
        ))
        XCTAssertEqual(belowProfile.state(.push)?.current.dose, .reps(3))
        XCTAssertEqual(Fixtures.lastTransition(belowProfile, factID: below.id)?.kind, .recordOnly)
    }

    func testManualTooHardBelowRegressesAboveDoesNotAndUnratedDoesNotChangeCapacity() throws {
        let below = Fixtures.evidence(id: 130, day: 1, variant: Fixtures.shallowWall, source: .manual,
                                      prescribed: nil, confirmed: .reps(1), setAmounts: [.reps(1)], effort: .tooHard)
        let belowProfile = Fixtures.profile(AdaptiveFacts(
            evidence: [below],
            calibrations: [Fixtures.calibration()]
        ))
        XCTAssertEqual(belowProfile.state(.push)?.current.variant, Fixtures.shallowWall)
        XCTAssertEqual(Fixtures.lastTransition(belowProfile, factID: below.id)?.kind, .decreaseDose)

        let above = Fixtures.evidence(id: 131, day: 1, variant: Fixtures.pushUp, source: .manual,
                                      prescribed: nil, confirmed: .reps(2), setAmounts: [.reps(2)], effort: .tooHard)
        let aboveProfile = Fixtures.profile(AdaptiveFacts(
            evidence: [above],
            calibrations: [Fixtures.calibration()]
        ))
        XCTAssertEqual(aboveProfile.state(.push)?.current.variant, Fixtures.wall)
        XCTAssertEqual(Fixtures.lastTransition(aboveProfile, factID: above.id)?.kind, .recordOnly)

        let unrated = Fixtures.evidence(id: 132, day: 1, source: .manual, prescribed: nil,
                                        confirmed: nil, effort: nil)
        let unratedProfile = Fixtures.profile(AdaptiveFacts(
            evidence: [unrated],
            calibrations: [Fixtures.calibration()]
        ))
        XCTAssertEqual(unratedProfile.state(.push)?.current.dose, .reps(3))
        XCTAssertTrue(Fixtures.lastTransition(unratedProfile, factID: unrated.id)?.rationale.codes.contains(.unrated) == true)
    }
}
