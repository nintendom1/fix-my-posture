import XCTest
@testable import AdaptiveTraining

final class TodaySessionPlannerTests: XCTestCase {
    func testNeedsCalibrationAndNothingOffered() {
        let empty = Fixtures.profile(.empty)
        XCTAssertEqual(AdaptiveReplay.todaySession(profile: empty, facts: .empty,
                                                   builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                                   calendar: Fixtures.calendar, asOf: Fixtures.date()), .needsCalibration)

        let removed = SettingsFact(id: Fixtures.id(220), recordedAt: Fixtures.date(day: 1),
                                   kind: .familyRemoved, family: .push)
        let facts = AdaptiveFacts(
            calibrations: [Fixtures.calibration()],
            settings: [removed]
        )
        let profile = Fixtures.profile(facts)
        XCTAssertEqual(profile.states.count, 1)
        XCTAssertTrue(profile.activeFamilies.isEmpty)
        XCTAssertEqual(AdaptiveReplay.todaySession(profile: profile, facts: facts,
                                                   builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                                   calendar: Fixtures.calendar, asOf: Fixtures.date(day: 2)), .nothingOffered)
    }

    func testNothingOfferedWhenTheFamiliesFloorIsNotBuilt() {
        let floor = ProgressionRung(id: VariantID(rawValue: "push.test_floor"), exerciseID: "test_floor",
                                    doseRange: .reps(1...5), isFloor: true)
        let main = ProgressionRung(id: VariantID(rawValue: "push.test_main"), exerciseID: "test_main",
                                   doseRange: .reps(1...8))
        let catalog = ProgressionCatalog(version: "planner-test",
                                         families: [MovementFamily(id: .push, debugName: "Push", rungs: [floor, main])])
        let calibration = Fixtures.calibration(id: 227, variant: main.id, dose: .reps(3))
        let facts = AdaptiveFacts(calibrations: [calibration])
        let profile = AdaptiveReplay.profile(facts: facts, catalog: catalog, builtExerciseIDs: ["test_main"],
                                             calendar: Fixtures.calendar)
        XCTAssertEqual(profile.states.count, 1)
        XCTAssertTrue(profile.activeFamilies.isEmpty)
        XCTAssertEqual(AdaptiveReplay.todaySession(profile: profile, facts: facts, catalog: catalog,
                                                    builtExerciseIDs: ["test_main"], calendar: Fixtures.calendar,
                                                    asOf: Fixtures.date(day: 1)), .nothingOffered)
    }

    func testRotationChoosesNeverPerformedThenLeastRecentAndCatalogOrderOnTie() throws {
        let starts = [
            CalibrationStart(family: .squat,
                             start: RungDose(variant: VariantID(rawValue: "squat.sit_to_stand"), dose: .reps(3))),
            CalibrationStart(family: .push, start: RungDose(variant: Fixtures.wall, dose: .reps(3)))
        ]
        let calibration = Fixtures.calibration(id: 221, families: [.squat, .push], starts: starts)
        let facts = AdaptiveFacts(
            calibrations: [calibration]
        )
        let profile = Fixtures.profile(facts)
        let tie = AdaptiveReplay.todaySession(profile: profile, facts: facts,
                                              builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                              calendar: Fixtures.calendar, asOf: Fixtures.date(day: 1))
        if case .ready(let session) = tie {
            XCTAssertEqual(session.family, .push)
        } else {
            XCTFail("Expected an available session.")
        }

        let pushed = Fixtures.evidence(id: 222, day: 1, family: .push, variant: Fixtures.wall,
                                       confirmed: nil, effort: nil)
        let performedFacts = AdaptiveFacts(
            evidence: [pushed],
            calibrations: [calibration]
        )
        let performed = Fixtures.profile(performedFacts)
        let next = AdaptiveReplay.todaySession(profile: performed, facts: performedFacts,
                                               builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                               calendar: Fixtures.calendar, asOf: Fixtures.date(day: 2))
        if case .ready(let session) = next {
            XCTAssertEqual(session.family, .squat)
        } else {
            XCTFail("Expected the least recently performed family.")
        }
    }

    func testCompletedTodayReturnsTheNextRotatedFamily() throws {
        let starts = [
            CalibrationStart(family: .push, start: RungDose(variant: Fixtures.wall, dose: .reps(3))),
            CalibrationStart(family: .squat,
                             start: RungDose(variant: VariantID(rawValue: "squat.sit_to_stand"), dose: .reps(3)))
        ]
        let calibration = Fixtures.calibration(id: 223, families: [.push, .squat], starts: starts)
        let prescription = Fixtures.prescription(id: 224, day: 2, itemID: 225, family: .push)
        let evidence = Fixtures.evidence(id: 226, day: 2, family: .push, variant: Fixtures.wall,
                                         confirmed: .reps(3), completion: .completed,
                                         itemID: 225, prescriptionID: 224)
        let facts = AdaptiveFacts(
            prescriptions: [prescription],
            evidence: [evidence],
            calibrations: [calibration]
        )
        let profile = Fixtures.profile(facts)
        let status = AdaptiveReplay.todaySession(profile: profile, facts: facts,
                                                  builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                                  calendar: Fixtures.calendar, asOf: Fixtures.date(day: 2))
        if case .completedToday(let family, let next) = status {
            XCTAssertEqual(family, .push)
            XCTAssertEqual(next?.family, .squat)
        } else {
            XCTFail("Expected today's main item to be recognized as complete.")
        }
    }

    func testAMainItemSwitchedToEasierCountsAsCompletedTodayButTheSwapItselfDoesNot() throws {
        let starts = [
            CalibrationStart(family: .push, start: RungDose(variant: Fixtures.wall, dose: .reps(6))),
            CalibrationStart(family: .squat,
                             start: RungDose(variant: VariantID(rawValue: "squat.sit_to_stand"), dose: .reps(3)))
        ]
        let calibration = Fixtures.calibration(id: 240, families: [.push, .squat], starts: starts)
        let main = Fixtures.prescription(id: 241, day: 2, itemID: 242, family: .push, dose: .reps(6))
        let swap = Fixtures.prescription(id: 243, day: 2, itemID: 244, family: .push, variant: Fixtures.shallowWall,
                                         dose: .reps(3), role: .easierSwap, offersBonus: false)
        let switched = Fixtures.evidence(id: 245, day: 2, prescribed: .reps(6), confirmed: .reps(2), effort: .tooHard,
                                         completion: .switchedToEasier, itemID: 242, prescriptionID: 241,
                                         midSetTooHard: true)
        let swapDone = Fixtures.evidence(id: 246, day: 2, variant: Fixtures.shallowWall, prescribed: .reps(3),
                                         confirmed: .reps(3), effort: .okay, itemID: 244, prescriptionID: 243)

        func status(_ facts: AdaptiveFacts) -> TodaySessionStatus {
            AdaptiveReplay.todaySession(profile: Fixtures.profile(facts), facts: facts,
                                        builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                        calendar: Fixtures.calendar, asOf: Fixtures.date(day: 2))
        }

        guard case .completedToday(let family, let next) = status(AdaptiveFacts(
            prescriptions: [main, swap], evidence: [switched], calibrations: [calibration])) else {
            return XCTFail("A main item switched to the easier version is today's main item done.")
        }
        XCTAssertEqual(family, .push)
        XCTAssertEqual(next?.family, .squat, "The rotation moves on.")

        // Only the swap done: the day's main item was never finished, so Today's Session is still offered.
        guard case .ready = status(AdaptiveFacts(prescriptions: [main, swap], evidence: [swapDone],
                                                 calibrations: [calibration])) else {
            return XCTFail("An easier swap alone isn't the day's main item.")
        }
    }

    func testTinyContextUsesMinimumDoseOmitsSampleAndDoesNotMutateProfile() throws {
        let first = Fixtures.evidence(id: 230, day: 1, prescribed: .reps(12), confirmed: .reps(12))
        let second = Fixtures.evidence(id: 231, day: 2, prescribed: .reps(12), confirmed: .reps(12))
        let facts = AdaptiveFacts(
            evidence: [first, second],
            calibrations: [Fixtures.calibration(dose: .reps(12))]
        )
        let profile = Fixtures.profile(facts)
        let before = profile
        let tiny = AdaptiveReplay.todaySession(profile: profile, facts: facts,
                                               builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                               calendar: Fixtures.calendar, asOf: Fixtures.date(day: 3),
                                               context: SessionContext(tiny: true))
        if case .ready(let session) = tiny {
            XCTAssertEqual(session.main.dose, .reps(1))
            XCTAssertNil(session.harderSample)
            XCTAssertTrue(session.isTiny)
            XCTAssertEqual(session.offersBonus, true)
        } else {
            XCTFail("Expected a tiny session.")
        }
        XCTAssertEqual(profile, before)
    }

    func testUnavailableCurrentRungFallsBackToNearestEasierBuiltRung() throws {
        let family = try XCTUnwrap(Fixtures.catalog.family(.push))
        let state = MovementState(family: .push,
                                  current: RungDose(variant: Fixtures.incline, dose: .reps(7)),
                                  confidence: .medium, lastChangedAt: Fixtures.date())
        let profile = AdaptiveProfile(policyVersion: .v1, catalogVersion: Fixtures.catalog.version,
                                      states: [state], activeFamilies: [.push], equipment: [], transitions: [])
        var built = Fixtures.allBuiltExerciseIDs
        built.remove("incline_push_up")
        let status = AdaptiveReplay.todaySession(profile: profile, facts: .empty, builtExerciseIDs: built,
                                                 calendar: Fixtures.calendar, asOf: Fixtures.date(day: 1))
        if case .ready(let session) = status {
            XCTAssertEqual(session.main.variant, Fixtures.wall)
            XCTAssertEqual(session.main.dose, .reps(1))
            XCTAssertEqual(session.rationale, "Push: starting point from calibration.")
        } else {
            XCTFail("Expected the available easier rung.")
        }
        XCTAssertEqual(Fixtures.catalog.family(.push)?.rungs.first?.minimumDose, family.rungs.first?.minimumDose)
    }

    func testCompletedTodayPicksTheLatestCompletionWhateverTheStoreOrder() {
        let squatFloor = VariantID(rawValue: "squat.sit_to_stand.partial")
        let calibration = Fixtures.calibration(families: [.push, .squat], starts: [
            CalibrationStart(family: .push, start: RungDose(variant: Fixtures.wall, dose: .reps(3))),
            CalibrationStart(family: .squat, start: RungDose(variant: squatFloor, dose: .reps(3)))
        ])
        let pushPrescription = Fixtures.prescription(id: 240, day: 1, itemID: 241)
        let squatPrescription = Fixtures.prescription(id: 242, day: 1, itemID: 243, family: .squat,
                                                      variant: squatFloor)
        let push = Fixtures.evidence(id: 244, day: 1, hour: 10, effort: .okay, itemID: 241, prescriptionID: 240)
        let squat = Fixtures.evidence(id: 245, day: 1, hour: 15, family: .squat, variant: squatFloor,
                                      effort: .okay, itemID: 243, prescriptionID: 242)
        for evidence in [[push, squat], [squat, push]] {
            let facts = AdaptiveFacts(prescriptions: [pushPrescription, squatPrescription], evidence: evidence,
                                      calibrations: [calibration])
            let status = AdaptiveReplay.todaySession(profile: Fixtures.profile(facts), facts: facts,
                                                     builtExerciseIDs: Fixtures.allBuiltExerciseIDs,
                                                     calendar: Fixtures.calendar, asOf: Fixtures.date(day: 1, hour: 18))
            guard case .completedToday(let family, _) = status else {
                return XCTFail("Expected completedToday, got \(status)")
            }
            XCTAssertEqual(family, .squat)
        }
    }
}
