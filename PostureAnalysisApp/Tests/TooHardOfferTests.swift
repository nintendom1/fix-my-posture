import AdaptiveTraining
import XCTest
@testable import PostureAnalysisApp

/// The mid-set "Too hard?" offer: when its button shows, that it never stops a set, what "Stop here" and "Easier
/// version" record, and that a tracker's status is never read as, or overwritten by, a Too Hard.
@MainActor
final class TooHardOfferTests: XCTestCase {
    private let prescriptionID = TooHardOfferTests.uuid(0x91)
    private let mainID = TooHardOfferTests.uuid(0x92)
    private let sampleID = TooHardOfferTests.uuid(0x93)
    private let swapID = TooHardOfferTests.uuid(0x94)
    private let shallow = VariantID(rawValue: "push.wall_push_up.shallow")
    private let wall = VariantID(rawValue: "push.wall_push_up")

    // MARK: - The button

    func testTheButtonShowsOnlyWhileASetIsUnderWayForASelfReportedItem() throws {
        let exercise = selfReported(target: 5, sets: 2)
        let routine = WorkoutPlan(id: UUID(), name: "My routine", items: [
            WorkoutPlanItem(id: TooHardOfferTests.uuid(0x64), exerciseID: exercise.id, sets: 2, targetReps: 5...5)
        ])
        let harness = makeHarness(exercises: [exercise], launch: nil, plan: routine, recorder: TooHardRecorder())
        open(harness)
        XCTAssertEqual(harness.model.session.phase, .ready)
        XCTAssertFalse(harness.model.hud.showsTooHardButton, "Ready: nothing to flag yet.")

        harness.model.send(.start)
        XCTAssertTrue(harness.model.hud.showsTooHardButton)

        harness.model.send(.pause)
        XCTAssertEqual(harness.model.session.phase, .paused(.user))
        XCTAssertTrue(harness.model.hud.showsTooHardButton, "A paused set is still a set.")

        harness.model.send(.resume)
        harness.model.send(.nextSet)
        XCTAssertEqual(harness.model.session.phase, .resting)
        XCTAssertFalse(harness.model.hud.showsTooHardButton, "Resting.")

        harness.model.send(.start)
        harness.model.send(.nextSet)
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete)
        XCTAssertFalse(harness.model.hud.showsTooHardButton, "Complete.")
    }

    func testTheButtonShowsOnlyWhileASetIsUnderWayForATimedItem() {
        let exercise = hold(seconds: 20)
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .seconds(20)),
                                  recorder: TooHardRecorder())
        open(harness)
        XCTAssertFalse(harness.model.hud.showsTooHardButton)

        harness.model.send(.start)
        XCTAssertTrue(harness.model.hud.showsTooHardButton)

        harness.scheduler.advance(by: 21)
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete)
        XCTAssertFalse(harness.model.hud.showsTooHardButton)
    }

    func testTheButtonShowsOnlyWhileASetIsUnderWayForACameraItem() {
        let wallPushUp = WallPushUpExercise.definition()
        let harness = makeHarness(exercises: [wallPushUp], launch: launch(exercise: wallPushUp, dose: .reps(1)),
                                  recorder: TooHardRecorder())
        open(harness)
        XCTAssertFalse(harness.model.hud.showsTooHardButton, "Framing.")
        var time = 0.0
        beginCameraSet(harness, exercise: wallPushUp, time: &time)
        XCTAssertEqual(harness.model.session.phase, .exercising)
        XCTAssertTrue(harness.model.hud.showsTooHardButton)

        finishCameraSet(harness, exercise: wallPushUp, time: &time)
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete)
        XCTAssertFalse(harness.model.hud.showsTooHardButton)
    }

    func testTheButtonStandsAsideForTheOpenOffer() {
        let exercise = selfReported(target: 5)
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: TooHardRecorder())
        open(harness)
        harness.model.send(.start)
        XCTAssertTrue(harness.model.hud.showsTooHardButton)

        harness.model.send(.tooHard)

        XCTAssertNotNil(harness.model.tooHardOffer)
        XCTAssertFalse(harness.model.hud.showsTooHardButton, "The offer's card takes the button's place.")
    }

    func testAnExerciseOutsideAnyPlanAndWithoutAnEngineCanStillBeFlagged() throws {
        let exercise = selfReported(target: 5)
        let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), exercises: [exercise],
                                               initialExercise: exercise.id)
        open(harness)
        harness.model.send(.start)

        harness.model.send(.tooHard)

        let offer = try XCTUnwrap(harness.model.tooHardOffer, "Every kind of exercise gets the offer.")
        XCTAssertNil(offer.easierVersion, "Only Today's Session offers an easier version.")
        harness.model.stopHere()
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete)
        XCTAssertNil(harness.model.tooHardOffer)
    }

    // MARK: - Opening the offer

    func testTheButtonAndTheVoiceCommandBothOpenTheOfferDuringASet() throws {
        let exercise = selfReported(target: 5)
        let recorder = TooHardRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        harness.voice.emit(.tooHard)
        XCTAssertNil(harness.model.tooHardOffer, "Before the set starts there is nothing to flag.")
        harness.model.send(.start)

        harness.voice.emit(.tooHard)

        XCTAssertNotNil(harness.model.tooHardOffer, "Saying \"too hard\" opens it.")
        harness.model.dismissTooHardOffer()
        XCTAssertNil(harness.model.tooHardOffer)
        harness.model.send(.tooHard)
        XCTAssertNotNil(harness.model.tooHardOffer, "So does the button, after a dismissal.")
        XCTAssertEqual(harness.model.session.phase, .exercising)
    }

    func testSayingTooHardWhenNoSetIsUnderWayDoesNothing() {
        let exercise = selfReported(target: 5)
        let recorder = TooHardRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextSet)
        XCTAssertNotNil(harness.model.effortCard)

        harness.voice.emit(.tooHard)
        harness.model.send(.tooHard)

        XCTAssertNil(harness.model.tooHardOffer, "An open question is about an item that already ended.")
        harness.model.rateEffort(.okay)
        XCTAssertEqual(recorder.evidence.first?.midSetTooHard, false, "Nothing was flagged.")
    }

    func testOpeningTheOfferTwiceKeepsOneOffer() throws {
        let exercise = selfReported(target: 5)
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: TooHardRecorder())
        open(harness)
        harness.model.send(.start)
        harness.model.send(.tooHard)
        let first = try XCTUnwrap(harness.model.tooHardOffer)

        harness.model.send(.tooHard)
        harness.voice.emit(.tooHard)

        XCTAssertEqual(harness.model.tooHardOffer, first)
    }

    // MARK: - Ignoring the offer

    func testIgnoringTheOfferKeepsTheSetGoingAndCountsNormally() throws {
        // Revert check (a): letting Too hard end the set at once makes this fail.
        let wallPushUp = WallPushUpExercise.definition()
        let recorder = TooHardRecorder()
        let harness = makeHarness(exercises: [wallPushUp], launch: launch(exercise: wallPushUp, dose: .reps(1)),
                                  recorder: recorder)
        open(harness)
        var time = 0.0
        beginCameraSet(harness, exercise: wallPushUp, time: &time)
        XCTAssertEqual(harness.model.session.phase, .exercising)

        harness.model.send(.tooHard)

        XCTAssertNotNil(harness.model.tooHardOffer)
        XCTAssertEqual(harness.model.session.phase, .exercising, "Flagging never stops the set.")
        XCTAssertTrue(harness.model.session.isCounting, "It never stops the counting either.")
        XCTAssertTrue(recorder.evidence.isEmpty)

        finishCameraSet(harness, exercise: wallPushUp, time: &time)

        XCTAssertEqual(harness.model.session.phase, .exerciseComplete, "The camera counted the rep as usual.")
        XCTAssertNil(harness.model.tooHardOffer, "The offer closes by itself when the set ends.")
        let card = try XCTUnwrap(harness.model.effortCard)
        XCTAssertNil(card.preselected, "Ignoring the offer is not an answer.")
        XCTAssertEqual(card.amount, 1)
        harness.model.rateEffort(.okay)

        let flagged = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertTrue(flagged.midSetTooHard)
        XCTAssertEqual(flagged.completion, .completed)
        XCTAssertEqual(flagged.effort, .okay, "Only the rating the user gives is the rating.")
        XCTAssertEqual(flagged.confirmed, .reps(1))

        // The same run with nobody tapping anything: the tracker's observation is exactly the same.
        let plainRecorder = TooHardRecorder()
        let plain = makeHarness(exercises: [wallPushUp], launch: launch(exercise: wallPushUp, dose: .reps(1)),
                                recorder: plainRecorder)
        open(plain)
        var plainTime = 0.0
        driveCameraSet(plain, exercise: wallPushUp, time: &plainTime)
        plain.model.rateEffort(.okay)
        let control = try XCTUnwrap(plainRecorder.evidence.first)
        XCTAssertFalse(control.midSetTooHard)
        XCTAssertEqual(flagged.tracker, control.tracker, "A Too hard tap never changes what the tracker saw.")
        XCTAssertEqual(flagged.tracker.status, .tracked)
        XCTAssertEqual(flagged.confirmation, control.confirmation)
        XCTAssertEqual(flagged.completion, control.completion)
    }

    func testIgnoringTheOfferOnASelfReportedSetFlagsItsEvidence() throws {
        let exercise = selfReported(target: 5)
        let recorder = TooHardRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.tooHard)

        harness.model.send(.nextSet)

        XCTAssertNil(harness.model.tooHardOffer, "The set ended, so the offer is gone.")
        let card = try XCTUnwrap(harness.model.effortCard)
        XCTAssertNil(card.preselected)
        harness.model.rateEffort(.easy)
        XCTAssertNil(harness.model.bonusOffer, "Nobody who said it was too hard is offered more.")
        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertTrue(evidence.midSetTooHard)
        XCTAssertEqual(evidence.completion, .completed)
        XCTAssertEqual(evidence.effort, .easy)
    }

    func testDismissingTheOfferKeepsTheSetGoingAndTheFlag() throws {
        let exercise = hold(seconds: 20)
        let recorder = TooHardRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .seconds(20)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.scheduler.advance(by: 5)
        harness.model.send(.tooHard)

        harness.model.dismissTooHardOffer()

        XCTAssertNil(harness.model.tooHardOffer)
        XCTAssertEqual(harness.model.session.phase, .exercising)
        harness.scheduler.advance(by: 16)
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete, "The hold ran its full length.")
        harness.model.rateEffort(.okay)
        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertTrue(evidence.midSetTooHard, "Closing the card doesn't take the flag back.")
        XCTAssertEqual(evidence.confirmed, .seconds(20))
        XCTAssertEqual(evidence.completion, .completed)
    }

    func testTheWorkoutEndingWithAFlaggedItemStillRecordsTheFlag() throws {
        let exercise = hold(seconds: 20)
        let recorder = TooHardRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .seconds(20)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.scheduler.advance(by: 6)
        harness.model.send(.tooHard)

        harness.model.send(.endWorkout)

        XCTAssertNil(harness.model.tooHardOffer)
        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertTrue(evidence.midSetTooHard)
        XCTAssertEqual(evidence.completion, .endedWorkout)
        XCTAssertNil(evidence.effort, "The workout ended: nobody rated anything.")
    }

    // MARK: - Stop here

    func testStopHereOnACameraItemEndsItWithTheCountedRepsAndPreselectsTooHard() throws {
        let wallPushUp = WallPushUpExercise.definition()
        let recorder = TooHardRecorder()
        let harness = makeHarness(exercises: [wallPushUp], launch: launch(exercise: wallPushUp, dose: .reps(3)),
                                  recorder: recorder)
        open(harness)
        var time = 0.0
        beginCameraSet(harness, exercise: wallPushUp, time: &time)
        driveCameraUntilReps(1, harness, exercise: wallPushUp, time: &time)
        XCTAssertEqual(harness.model.session.repCount, 1)
        harness.model.send(.tooHard)

        harness.model.stopHere()

        XCTAssertNil(harness.model.tooHardOffer)
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete, "The item ended with what was done.")
        let card = try XCTUnwrap(harness.model.effortCard)
        XCTAssertEqual(card.amount, 1)
        XCTAssertEqual(card.preselected, .tooHard)
        XCTAssertTrue(recorder.evidence.isEmpty, "The user can still change the answer.")

        harness.model.rateEffort(.tooHard)

        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(evidence.completion, .stoppedEarly)
        XCTAssertEqual(evidence.confirmed, .reps(1))
        XCTAssertEqual(evidence.prescribed, .reps(3))
        XCTAssertEqual(evidence.confirmation, .trackerAccepted, "A rated count the user didn't change.")
        XCTAssertEqual(evidence.effort, .tooHard)
        XCTAssertTrue(evidence.midSetTooHard)
        XCTAssertEqual(evidence.tracker.status, .tracked)
        XCTAssertEqual(evidence.tracker.observed, .reps(1))
    }

    func testStopHereOnATimedItemEndsItWithTheSecondsHeld() throws {
        let exercise = hold(seconds: 20)
        let recorder = TooHardRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .seconds(20)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.scheduler.advance(by: 8)
        harness.model.send(.tooHard)

        harness.model.stopHere()

        let card = try XCTUnwrap(harness.model.effortCard)
        XCTAssertEqual(card.unit, .seconds)
        XCTAssertEqual(card.amount, 8)
        XCTAssertEqual(card.preselected, .tooHard)
        harness.model.rateEffort(.tooHard)

        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(evidence.completion, .stoppedEarly)
        XCTAssertEqual(evidence.confirmed, .seconds(8))
        XCTAssertEqual(evidence.confirmation, .user, "A hold's seconds are the user's own timer.")
        XCTAssertEqual(evidence.effort, .tooHard)
        XCTAssertTrue(evidence.midSetTooHard)
    }

    func testStopHereOnASelfReportedItemStartsTheCardAtThePrescribedAmountAndTheUserCorrectsIt() throws {
        let exercise = selfReported(target: 5)
        let recorder = TooHardRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.tooHard)

        harness.model.stopHere()

        let card = try XCTUnwrap(harness.model.effortCard)
        XCTAssertEqual(card.amount, 5, "Nobody counted these reps: the card starts at the prescribed amount.")
        XCTAssertEqual(card.preselected, .tooHard)
        harness.model.adjustEffortAmount(by: -2)
        harness.model.rateEffort(.tooHard)

        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(evidence.confirmed, .reps(3), "The amount the user confirmed on the card.")
        XCTAssertEqual(evidence.confirmation, .user)
        XCTAssertEqual(evidence.completion, .stoppedEarly)
        XCTAssertTrue(evidence.midSetTooHard)
    }

    func testStopHereAtTheFullPrescribedAmountStillReadsAsStoppedEarly() throws {
        let exercise = selfReported(target: 5)
        let recorder = TooHardRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.tooHard)
        harness.model.stopHere()

        harness.model.rateEffort(.okay)

        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(evidence.completion, .stoppedEarly, "The user chose to stop; that is the reason recorded.")
        XCTAssertEqual(evidence.effort, .okay, "The user changed the answer, and that wins.")
        XCTAssertTrue(evidence.midSetTooHard)
    }

    func testStartingTheNextSetClosesThePreselectedCardAsTooHard() throws {
        let exercise = selfReported(target: 5)
        let recorder = TooHardRecorder()
        let harness = makeHarness(exercises: [exercise],
                                  launch: launch(exercise: exercise, dose: .reps(5), withSample: true),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.tooHard)
        harness.model.stopHere()
        XCTAssertNotNil(harness.model.effortCard)
        XCTAssertEqual(harness.model.session.phase, .resting, "The optional sample is next.")

        harness.model.send(.start)

        XCTAssertNil(harness.model.effortCard)
        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(evidence.prescriptionItemID, mainID)
        XCTAssertEqual(evidence.effort, .tooHard, "The user said it was too hard and never took it back.")
        XCTAssertEqual(evidence.completion, .stoppedEarly)
        XCTAssertTrue(evidence.midSetTooHard)
    }

    func testSkippingThePreselectedCardRecordsNoRatingButKeepsTheFlag() throws {
        let exercise = selfReported(target: 5)
        let recorder = TooHardRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.tooHard)
        harness.model.stopHere()

        harness.model.skipEffort()

        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertNil(evidence.effort, "Skip is the user declining to rate.")
        XCTAssertTrue(evidence.midSetTooHard)
        XCTAssertEqual(evidence.completion, .stoppedEarly)
    }

    func testStopHereOnAMultiSetPlanItemSkipsItsRemainingSets() throws {
        let exercise = selfReported(target: 5, sets: 3)
        let recorder = TooHardRecorder()
        let routine = WorkoutPlan(id: UUID(), name: "My routine", items: [
            WorkoutPlanItem(id: TooHardOfferTests.uuid(0x61), exerciseID: exercise.id, sets: 3, targetReps: 5...5),
            WorkoutPlanItem(id: TooHardOfferTests.uuid(0x62), exerciseID: exercise.id, sets: 1, targetReps: 5...5)
        ])
        let harness = makeHarness(exercises: [exercise], launch: nil, plan: routine, recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextSet)
        harness.model.send(.start)
        harness.model.send(.tooHard)

        harness.model.stopHere()

        let record = harness.model.session.planRecords[TooHardOfferTests.uuid(0x61)]
        XCTAssertEqual(record?.setReps, [5, 5], "Two sets were done; the third was never started.")
        XCTAssertEqual(record?.outcome, .skipped)
        XCTAssertEqual(harness.model.session.currentPlanItem?.id, TooHardOfferTests.uuid(0x62), "On to the next item.")
        XCTAssertEqual(harness.model.session.phase, .ready)
        XCTAssertNil(harness.model.tooHardOffer)
    }

    // MARK: - Stop here on a standalone exercise with sets left (review finding 1)

    /// A Quick Start exercise (no plan) that is the current rung of an active family, so its card opens.
    private func standaloneHarness(_ exercise: ExerciseDefinition, recorder: TooHardRecorder,
                                   dose: Dose) -> WorkoutCoachHarness {
        recorder.setRung(ActiveRung(family: .push, rungDose: RungDose(variant: wall, dose: dose)), for: exercise.id)
        return WorkoutCoachHarness.make(preferences: InMemoryPreferences(), exercises: [exercise],
                                        initialExercise: exercise.id, adaptive: recorder)
    }

    func testStopHereEndsATwoSetStandaloneCameraExerciseAndNothingRestartsAfterTheOldRestDeadline() throws {
        // Revert check (finding 1): ending only the current set rests, shows no card, and starts set two later.
        let wallPushUp = WallPushUpExercise.definition().withTarget(sets: 2, reps: 3...3)
        let recorder = TooHardRecorder()
        let harness = standaloneHarness(wallPushUp, recorder: recorder, dose: .reps(3))
        open(harness)
        var time = 0.0
        beginCameraSet(harness, exercise: wallPushUp, time: &time)
        driveCameraUntilReps(1, harness, exercise: wallPushUp, time: &time)
        XCTAssertEqual(harness.model.session.repCount, 1)
        harness.model.send(.tooHard)

        harness.model.stopHere()

        XCTAssertEqual(harness.model.session.phase, .exerciseComplete, "The item ended; it is not resting for set two.")
        XCTAssertNil(harness.model.session.restRemaining(at: harness.clock.now), "No rest was scheduled.")
        XCTAssertEqual(harness.model.session.progress[wallPushUp.id]?.setReps, [1], "The current amount is kept.")
        XCTAssertFalse(harness.model.session.isCounting)
        let card = try XCTUnwrap(harness.model.effortCard, "The card opens at once.")
        XCTAssertEqual(card.amount, 1)
        XCTAssertEqual(card.preselected, .tooHard)
        XCTAssertTrue(recorder.evidence.isEmpty)

        // Well past where a rest would have ended, with the camera still delivering the exercise's movement.
        harness.scheduler.advance(by: 300)
        for _ in 0..<60 { frame(harness, exercise: wallPushUp, time: &time) }
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete, "Nothing restarts.")
        XCTAssertFalse(harness.model.session.isCounting)
        XCTAssertEqual(harness.model.session.progress[wallPushUp.id]?.setReps, [1])

        harness.model.rateEffort(.tooHard)
        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(evidence.source, .manual)
        XCTAssertEqual(evidence.completion, .stoppedEarly)
        XCTAssertEqual(evidence.confirmed, .reps(1))
        XCTAssertEqual(evidence.effort, .tooHard)
        XCTAssertTrue(evidence.midSetTooHard)
        XCTAssertEqual(evidence.tracker.status, .tracked)
        XCTAssertEqual(evidence.tracker.observed, .reps(1))
        let record = try savedRecord(harness)
        XCTAssertEqual(record.entries.map(\.sets.count), [1], "One set was saved, and no second one.")
    }

    func testStopHereEndsATwoSetStandaloneTimedHoldAndNothingRestartsAfterTheOldRestDeadline() throws {
        var exercise = hold(seconds: 20)
        exercise.sets = 2
        let recorder = TooHardRecorder()
        let harness = standaloneHarness(exercise, recorder: recorder, dose: .seconds(20))
        open(harness)
        harness.model.send(.start)
        harness.scheduler.advance(by: 8)
        harness.model.send(.tooHard)

        harness.model.stopHere()

        XCTAssertEqual(harness.model.session.phase, .exerciseComplete)
        XCTAssertNil(harness.model.session.restRemaining(at: harness.clock.now))
        XCTAssertNil(harness.model.session.holdRemaining(at: harness.clock.now), "No hold is left running.")
        let card = try XCTUnwrap(harness.model.effortCard)
        XCTAssertEqual(card.unit, .seconds)
        XCTAssertEqual(card.amount, 8, "The seconds held are kept.")
        XCTAssertEqual(card.preselected, .tooHard)

        harness.scheduler.advance(by: 300)
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete, "Nothing restarts after the old rest deadline.")
        XCTAssertEqual(harness.model.session.progress[exercise.id]?.setReps, [8])
        harness.model.rateEffort(.tooHard)
        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(evidence.completion, .stoppedEarly)
        XCTAssertEqual(evidence.confirmed, .seconds(8))
        XCTAssertEqual(evidence.confirmation, .user)
        XCTAssertTrue(evidence.midSetTooHard)
    }

    func testStopHereEndsATwoSetStandaloneSelfReportedExerciseAndTheUserConfirmsThePartialAmount() throws {
        let exercise = selfReported(target: 5, sets: 2)
        let recorder = TooHardRecorder()
        let harness = standaloneHarness(exercise, recorder: recorder, dose: .reps(5))
        open(harness)
        harness.model.send(.start)
        harness.model.send(.tooHard)

        harness.model.stopHere()

        XCTAssertEqual(harness.model.session.phase, .exerciseComplete)
        XCTAssertNil(harness.model.session.restRemaining(at: harness.clock.now))
        let card = try XCTUnwrap(harness.model.effortCard, "The partial amount can be confirmed at once.")
        XCTAssertEqual(card.amount, 5, "Nobody counted these reps: the card starts at the prescribed amount.")
        XCTAssertEqual(card.preselected, .tooHard)

        harness.model.adjustEffortAmount(by: -2)
        harness.scheduler.advance(by: 300)
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete, "Nothing restarts after the old rest deadline.")
        XCTAssertEqual(harness.model.effortCard?.amount, 3, "The open card is untouched by time passing.")
        harness.model.rateEffort(.tooHard)

        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(evidence.confirmed, .reps(3))
        XCTAssertEqual(evidence.confirmation, .user)
        XCTAssertEqual(evidence.completion, .stoppedEarly)
        XCTAssertEqual(evidence.effort, .tooHard)
        XCTAssertTrue(evidence.midSetTooHard)
        let record = try savedRecord(harness)
        XCTAssertEqual(record.entries.map(\.sets.count), [1])
    }

    func testStopHereAfterAFinishedSetKeepsBothSetsAndTheSmallestAmountOnTheCard() throws {
        let exercise = selfReported(target: 5, sets: 3)
        let recorder = TooHardRecorder()
        let harness = standaloneHarness(exercise, recorder: recorder, dose: .reps(5))
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextSet)
        XCTAssertEqual(harness.model.session.phase, .resting)
        harness.model.send(.start)
        harness.model.send(.tooHard)

        harness.model.stopHere()

        XCTAssertEqual(harness.model.session.phase, .exerciseComplete, "The third set is never scheduled.")
        XCTAssertEqual(harness.model.session.progress[exercise.id]?.setReps, [5, 5])
        let card = try XCTUnwrap(harness.model.effortCard)
        XCTAssertEqual(card.setCount, 2)
        XCTAssertEqual(card.preselected, .tooHard)
    }

    func testAnotherRoundStillWorksAfterStoppingAStandaloneExercise() {
        let exercise = selfReported(target: 5, sets: 2)
        let harness = standaloneHarness(exercise, recorder: TooHardRecorder(), dose: .reps(5))
        open(harness)
        harness.model.send(.start)
        harness.model.send(.tooHard)
        harness.model.stopHere()
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete)

        harness.model.send(.anotherRound)

        XCTAssertEqual(harness.model.session.phase, .ready)
        XCTAssertEqual(harness.model.session.currentSetNumber, 1, "A new round starts at set 1.")
    }

    func testTheReducerStopsAStandaloneExerciseOnlyWhileASetIsUnderWay() throws {
        var idle = WorkoutSession(exercises: [selfReported(target: 5, sets: 2)], initialExercise: .shoulderPress)
        _ = idle.handle(.opened, at: 0)
        XCTAssertEqual(idle.phase, .ready)
        XCTAssertTrue(idle.handle(.command(.stopItem), at: 1).isEmpty, "Nothing is under way.")
        XCTAssertEqual(idle.phase, .ready)

        var session = idle
        _ = session.handle(.command(.start), at: 2)
        let effects = session.handle(.command(.stopItem), at: 3)
        XCTAssertFalse(effects.isEmpty)
        XCTAssertEqual(session.phase, .exerciseComplete)
        XCTAssertNil(session.restEndsAt)
        XCTAssertEqual(session.progress[.shoulderPress]?.setReps, [5])
        XCTAssertTrue(session.handle(.command(.stopItem), at: 4).isEmpty, "Twice is once.")
        XCTAssertEqual(session.progress[.shoulderPress]?.setReps, [5])

        // In a plan the item's remaining sets are skipped with Next Exercise instead, so the command does nothing.
        var planned = makeSession(withSample: false, mainSets: 2)
        _ = planned.handle(.command(.start), at: 2)
        XCTAssertTrue(planned.handle(.command(.stopItem), at: 3).isEmpty)
        XCTAssertEqual(planned.phase, .exercising)
    }

    // MARK: - Stop here during a bonus (review finding 3)

    /// Today's Session with a timed main item and a harder sample, the main item rated Easy and its bonus taken and started.
    private func runningTimedBonus(recorder: TooHardRecorder) -> WorkoutCoachHarness {
        let exercise = hold(seconds: 20)
        let harness = makeHarness(exercises: [exercise],
                                  launch: launch(exercise: exercise, dose: .seconds(20), withSample: true),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.scheduler.advance(by: 21)
        harness.model.rateEffort(.easy)
        harness.model.acceptBonus()
        harness.model.send(.start)
        harness.scheduler.advance(by: 3)
        return harness
    }

    func testStopHereDuringATimedBonusOpensItsCardOnTooHardAndKeepsTheItemsOwnRating() throws {
        // Revert check (finding 3): without consuming the choice the bonus card has no preselection and records unrated.
        let recorder = TooHardRecorder()
        let harness = runningTimedBonus(recorder: recorder)
        XCTAssertTrue(recorder.evidence.isEmpty)
        harness.model.send(.tooHard)
        let offer = try XCTUnwrap(harness.model.tooHardOffer)
        XCTAssertNil(offer.easierVersion, "A bonus has no easier version.")

        harness.model.stopHere()

        let card = try XCTUnwrap(harness.model.effortCard)
        XCTAssertTrue(card.isBonus)
        XCTAssertEqual(card.amount, 3, "The seconds held.")
        XCTAssertEqual(card.preselected, .tooHard)
        XCTAssertTrue(recorder.evidence.isEmpty, "Still waiting for the bonus to be settled.")

        // Starting the next set closes the card without a choice: the preselected answer is recorded.
        harness.model.send(.start)

        XCTAssertNil(harness.model.effortCard)
        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(recorder.evidence.count, 1, "One row for the item, with its bonus.")
        XCTAssertEqual(evidence.prescriptionItemID, mainID)
        XCTAssertEqual(evidence.effort, .easy, "The prescribed item's own rating is kept.")
        XCTAssertEqual(evidence.completion, .completed)
        XCTAssertEqual(evidence.bonus,
                       BonusRecord(offered: .seconds(5), accepted: true, completed: .seconds(3), effort: .tooHard))
    }

    func testAnExplicitAnswerOrSkipOnTheStoppedBonusCardWins() throws {
        let skipped = TooHardRecorder()
        let first = runningTimedBonus(recorder: skipped)
        first.model.send(.tooHard)
        first.model.stopHere()
        first.model.skipEffort()
        XCTAssertEqual(skipped.evidence.first?.bonus,
                       BonusRecord(offered: .seconds(5), accepted: true, completed: .seconds(3)),
                       "Skip is the user declining to rate the bonus.")

        let changed = TooHardRecorder()
        let second = runningTimedBonus(recorder: changed)
        second.model.send(.tooHard)
        second.model.stopHere()
        second.model.rateEffort(.okay)
        XCTAssertEqual(changed.evidence.first?.bonus?.effort, .okay)
        XCTAssertEqual(changed.evidence.first?.effort, .easy)
    }

    func testIgnoringTheOfferDuringABonusPreselectsNothingOnItsCard() throws {
        let recorder = TooHardRecorder()
        let harness = runningTimedBonus(recorder: recorder)
        harness.model.send(.tooHard)

        harness.model.dismissTooHardOffer()
        harness.scheduler.advance(by: 3)

        let card = try XCTUnwrap(harness.model.effortCard, "The five-second hold ran its course.")
        XCTAssertTrue(card.isBonus)
        XCTAssertEqual(card.amount, 5)
        XCTAssertNil(card.preselected, "Ignoring the offer is not an answer.")
        harness.model.rateEffort(.okay)
        XCTAssertEqual(recorder.evidence.first?.bonus,
                       BonusRecord(offered: .seconds(5), accepted: true, completed: .seconds(5), effort: .okay))
    }

    // MARK: - Easier version

    func testEasierVersionEndsTheItemAndRunsWhatTheEngineChoseInItsPlace() throws {
        let main = selfReported(target: 5)
        let easier = selfReported(from: HammerCurlExercise.definition(), target: 5)
        let recorder = TooHardRecorder()
        recorder.option = EasierSwapOption(target: RungDose(variant: shallow, dose: .reps(3)), exerciseID: easier.id,
                                           reducedRange: false)
        let harness = makeHarness(exercises: [main, easier], launch: launch(exercise: main, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.tooHard)
        let offer = try XCTUnwrap(harness.model.tooHardOffer)
        XCTAssertEqual(offer.easierVersion, TooHardOfferState.EasierVersion(name: easier.displayName, amountLabel: "3 reps"))
        XCTAssertEqual(recorder.askedFor, [mainID], "The app asks the engine, about the main item.")

        harness.model.takeEasierVersion()

        // The swap prescription was issued, and the main item ended with what was done.
        XCTAssertEqual(recorder.issued.count, 1)
        let issued = try XCTUnwrap(recorder.issued.first)
        XCTAssertEqual(recorder.issuedReplacing, [mainID])
        XCTAssertNil(harness.model.tooHardOffer)
        let items = try XCTUnwrap(harness.model.session.plan?.items)
        XCTAssertEqual(items.map(\.isEasierSwap), [false, true])
        let swap = try XCTUnwrap(items.dropFirst().first)
        XCTAssertEqual(swap.id, issued.item.itemID)
        XCTAssertEqual(swap.exerciseID, easier.id, "The easier rung can be another exercise.")
        XCTAssertEqual(swap.targetReps, 3...3)
        XCTAssertEqual(swap.sets, 1)
        XCTAssertEqual(swap.label(for: easier), "Easier: \(easier.displayName)")
        XCTAssertEqual(harness.model.session.currentPlanItem?.id, swap.id)
        XCTAssertEqual(harness.model.session.exercise?.id, easier.id)
        XCTAssertEqual(harness.model.session.exercise?.targetReps, 3...3)
        XCTAssertEqual(harness.model.session.phase, .ready, "Set up like a plan item, ready to start.")
        XCTAssertEqual(harness.model.session.planPositionLabel, "Easier version")

        // The main item's question is still open, on Too Hard.
        let card = try XCTUnwrap(harness.model.effortCard)
        XCTAssertEqual(card.preselected, .tooHard)
        XCTAssertEqual(card.amount, 5)
        XCTAssertTrue(recorder.evidence.isEmpty)

        harness.model.send(.start)
        XCTAssertNil(harness.model.effortCard, "Starting the easier set closes the card.")
        let mainEvidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(mainEvidence.prescriptionItemID, mainID)
        XCTAssertEqual(mainEvidence.completion, .switchedToEasier)
        XCTAssertEqual(mainEvidence.effort, .tooHard)
        XCTAssertTrue(mainEvidence.midSetTooHard)
        XCTAssertEqual(mainEvidence.confirmed, .reps(5))

        harness.model.send(.nextSet)
        let swapCard = try XCTUnwrap(harness.model.effortCard, "After that item, its own card appears.")
        XCTAssertNil(swapCard.preselected)
        XCTAssertEqual(swapCard.amount, 3)
        harness.model.rateEffort(.okay)

        XCTAssertEqual(recorder.evidence.count, 2)
        let swapEvidence = try XCTUnwrap(recorder.evidence.last)
        XCTAssertEqual(swapEvidence.prescriptionID, issued.prescriptionID, "It carries its own prescription.")
        XCTAssertEqual(swapEvidence.prescriptionItemID, issued.item.itemID)
        XCTAssertEqual(swapEvidence.source, .adaptive)
        XCTAssertEqual(swapEvidence.variant, shallow)
        XCTAssertEqual(swapEvidence.prescribed, .reps(3))
        XCTAssertEqual(swapEvidence.confirmed, .reps(3))
        XCTAssertEqual(swapEvidence.completion, .completed)
        XCTAssertEqual(swapEvidence.effort, .okay)
        XCTAssertFalse(swapEvidence.midSetTooHard)
        XCTAssertNil(swapEvidence.bonus)
    }

    func testAnEasySwapNeverOffersABonus() throws {
        let main = selfReported(target: 5)
        let recorder = TooHardRecorder()
        recorder.option = EasierSwapOption(target: RungDose(variant: shallow, dose: .reps(3)), exerciseID: main.id,
                                           reducedRange: false)
        let harness = makeHarness(exercises: [main], launch: launch(exercise: main, dose: .reps(5)), recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.tooHard)
        harness.model.takeEasierVersion()
        harness.model.send(.start)
        harness.model.send(.nextSet)

        harness.model.rateEffort(.easy)

        XCTAssertNil(harness.model.bonusOffer)
        XCTAssertEqual(recorder.evidence.count, 2)
        XCTAssertNil(recorder.evidence.last?.bonus)
    }

    func testTheSwapRunsExactlyWhatTheEngineReturnedWhateverTheMainItemWas() throws {
        // Revert check (b): the app holds no dose or rung arithmetic; this fake's answer is used as it is, and the
        // package tests cover every branch of where the answer comes from.
        let main = selfReported(target: 12)
        let recorder = TooHardRecorder()
        recorder.option = EasierSwapOption(target: RungDose(variant: shallow, dose: .reps(7)), exerciseID: main.id,
                                           reducedRange: false)
        let harness = makeHarness(exercises: [main], launch: launch(exercise: main, dose: .reps(12)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.tooHard)
        XCTAssertEqual(harness.model.tooHardOffer?.easierVersion?.amountLabel, "7 reps")

        harness.model.takeEasierVersion()

        XCTAssertEqual(harness.model.session.plan?.items.last?.targetReps, 7...7)
        XCTAssertEqual(recorder.issuedTargets, [RungDose(variant: shallow, dose: .reps(7))])
    }

    func testWhenTheEngineHasNoEasierVersionOnlyStopHereIsOffered() throws {
        let exercise = selfReported(target: 5)
        let recorder = TooHardRecorder()
        recorder.option = nil
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)

        harness.model.send(.tooHard)

        let offer = try XCTUnwrap(harness.model.tooHardOffer)
        XCTAssertNil(offer.easierVersion)
        XCTAssertEqual(recorder.askedFor, [mainID], "The engine was asked, and had nothing.")
        harness.model.takeEasierVersion()
        XCTAssertNotNil(harness.model.tooHardOffer, "There is nothing to take, so nothing happens.")
        XCTAssertEqual(harness.model.session.phase, .exercising)
        XCTAssertEqual(harness.model.session.plan?.items.count, 1)
        XCTAssertTrue(recorder.issued.isEmpty)
        harness.model.stopHere()
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete, "Stop here still works.")
    }

    func testWhenTheSwapCannotBeSavedTheOfferKeepsOnlyStopHere() throws {
        let exercise = selfReported(target: 5)
        let recorder = TooHardRecorder()
        recorder.option = EasierSwapOption(target: RungDose(variant: shallow, dose: .reps(3)), exerciseID: exercise.id,
                                           reducedRange: false)
        recorder.failsToIssue = true
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.tooHard)
        XCTAssertNotNil(harness.model.tooHardOffer?.easierVersion)

        harness.model.takeEasierVersion()

        XCTAssertEqual(harness.model.session.phase, .exercising, "Nothing was taken, so nothing ended.")
        XCTAssertEqual(harness.model.session.plan?.items.count, 1)
        XCTAssertNotNil(harness.model.tooHardOffer)
        XCTAssertNil(harness.model.tooHardOffer?.easierVersion)
    }

    func testManualWorkNeverOffersAnEasierVersionOrEvenAsksForOne() throws {
        let exercise = selfReported(target: 5)
        let recorder = TooHardRecorder()
        recorder.setRung(ActiveRung(family: .push, rungDose: RungDose(variant: wall, dose: .reps(5))), for: exercise.id)
        recorder.option = EasierSwapOption(target: RungDose(variant: shallow, dose: .reps(3)), exerciseID: exercise.id,
                                           reducedRange: false)
        let routine = WorkoutPlan(id: UUID(), name: "My routine", items: [
            WorkoutPlanItem(id: TooHardOfferTests.uuid(0x63), exerciseID: exercise.id, sets: 1, targetReps: 5...5)
        ])
        let harness = makeHarness(exercises: [exercise], launch: nil, plan: routine, recorder: recorder)
        open(harness)
        harness.model.send(.start)

        harness.model.send(.tooHard)

        let offer = try XCTUnwrap(harness.model.tooHardOffer, "A routine exercise still gets Stop here.")
        XCTAssertNil(offer.easierVersion)
        XCTAssertTrue(recorder.askedFor.isEmpty, "The engine isn't asked about manual work.")
        harness.model.takeEasierVersion()
        XCTAssertEqual(harness.model.session.phase, .exercising)
        XCTAssertTrue(recorder.issued.isEmpty)

        // Stop here records the flag on the manual evidence too.
        harness.model.stopHere()
        harness.model.rateEffort(.tooHard)
        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(evidence.source, .manual)
        XCTAssertTrue(evidence.midSetTooHard)
        XCTAssertEqual(evidence.completion, .stoppedEarly)
    }

    func testTheHarderSampleNeverOffersAnEasierVersion() throws {
        let exercise = selfReported(target: 5)
        let recorder = TooHardRecorder()
        recorder.option = EasierSwapOption(target: RungDose(variant: shallow, dose: .reps(3)), exerciseID: exercise.id,
                                           reducedRange: false)
        let harness = makeHarness(exercises: [exercise],
                                  launch: launch(exercise: exercise, dose: .reps(5), withSample: true),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextSet)
        harness.model.rateEffort(.okay)
        harness.model.send(.start)
        XCTAssertEqual(harness.model.session.currentPlanItem?.id, sampleID)
        XCTAssertEqual(harness.model.session.phase, .exercising)

        harness.model.send(.tooHard)

        let offer = try XCTUnwrap(harness.model.tooHardOffer)
        XCTAssertNil(offer.easierVersion, "A harder sample is optional; the way out is to stop.")
        XCTAssertTrue(recorder.askedFor.isEmpty)
        harness.model.takeEasierVersion()
        XCTAssertEqual(harness.model.session.plan?.items.filter(\.isEasierSwap).count, 0)
    }

    func testAnEasierVersionRunsAfterTheMainItemAndBeforeTheSample() throws {
        let exercise = selfReported(target: 5)
        let recorder = TooHardRecorder()
        recorder.option = EasierSwapOption(target: RungDose(variant: shallow, dose: .reps(3)), exerciseID: exercise.id,
                                           reducedRange: false)
        let harness = makeHarness(exercises: [exercise],
                                  launch: launch(exercise: exercise, dose: .reps(5), withSample: true),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.tooHard)

        harness.model.takeEasierVersion()

        let items = try XCTUnwrap(harness.model.session.plan?.items)
        XCTAssertEqual(items.map(\.id), [mainID, recorder.issued.first?.item.itemID ?? swapID, sampleID])
        XCTAssertEqual(items.map(\.isEasierSwap), [false, true, false])
        XCTAssertEqual(harness.model.session.currentPlanItem?.isEasierSwap, true, "The sample still follows.")
        XCTAssertEqual(harness.model.session.phase, .ready)
    }

    func testAnEasierVersionAtACameraItemRunsTheReducedRangeVariantAndTheCameraCountsIt() throws {
        let wallPushUp = WallPushUpExercise.definition()
        let shallowExercise = try XCTUnwrap(wallPushUp.reducedRange?())
        let recorder = TooHardRecorder()
        recorder.option = EasierSwapOption(target: RungDose(variant: shallow, dose: .reps(1)), exerciseID: wallPushUp.id,
                                           reducedRange: true)
        let harness = makeHarness(exercises: [wallPushUp], launch: launch(exercise: wallPushUp, dose: .reps(3)),
                                  recorder: recorder)
        open(harness)
        var time = 0.0
        beginCameraSet(harness, exercise: wallPushUp, time: &time)
        harness.model.send(.tooHard)
        XCTAssertEqual(harness.model.tooHardOffer?.easierVersion?.name, shallowExercise.displayName)

        harness.model.takeEasierVersion()

        let swap = try XCTUnwrap(harness.model.session.plan?.items.dropFirst().first)
        XCTAssertTrue(swap.reducedRange)
        XCTAssertEqual(swap.label(for: wallPushUp), "Easier: \(shallowExercise.displayName)")
        XCTAssertEqual(harness.model.session.exercise?.displayName, shallowExercise.displayName)
        driveCameraSet(harness, exercise: shallowExercise, time: &time)
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete, "The camera counted the easier rep.")
        let card = try XCTUnwrap(harness.model.effortCard)
        XCTAssertEqual(card.amount, 1)
        harness.model.rateEffort(.okay)
        XCTAssertEqual(recorder.evidence.count, 2)
        XCTAssertEqual(recorder.evidence.last?.tracker.status, .tracked)
        XCTAssertEqual(recorder.evidence.last?.tracker.observed, .reps(1))
    }

    func testAnEasierVersionNobodyDoesAnythingInIsNeverSkippedAndLeavesNoEntry() throws {
        let main = selfReported(target: 5)
        let recorder = TooHardRecorder()
        recorder.option = EasierSwapOption(target: RungDose(variant: shallow, dose: .reps(3)), exerciseID: main.id,
                                           reducedRange: false)
        let harness = makeHarness(exercises: [main], launch: launch(exercise: main, dose: .reps(5)), recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.tooHard)
        harness.model.takeEasierVersion()
        harness.model.send(.start)
        harness.model.send(.nextExercise)

        let record = try savedRecord(harness)

        XCTAssertEqual(record.entries.map(\.name), [main.displayName], "A swap with no work stays out of history.")
        XCTAssertFalse(record.entries.contains { $0.outcome == .skipped })
        let stats = WorkoutCompletionStats(record: record)
        XCTAssertFalse(stats.exerciseRows.map(\.summary).contains { $0.contains("Skipped") })
    }

    // MARK: - Saved names and completion copy

    func testTheSavedWorkoutNamesAnEasierVersionAndNeverCallsItSkipped() throws {
        let main = selfReported(target: 5)
        let easier = selfReported(from: HammerCurlExercise.definition(), target: 5)
        let recorder = TooHardRecorder()
        recorder.option = EasierSwapOption(target: RungDose(variant: shallow, dose: .reps(3)), exerciseID: easier.id,
                                           reducedRange: false)
        let harness = makeHarness(exercises: [main, easier], launch: launch(exercise: main, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.tooHard)
        harness.model.takeEasierVersion()
        harness.model.send(.start)
        harness.model.send(.nextSet)
        harness.model.rateEffort(.okay)

        let record = try savedRecord(harness)

        XCTAssertEqual(record.entries.map(\.name), [main.displayName, "Easier: \(easier.displayName)"])
        XCTAssertEqual(record.entries.map(\.outcome), [.completed, .completed])
        let stats = WorkoutCompletionStats(record: record)
        XCTAssertEqual(stats.exerciseRows.map(\.isEasierSwap), [false, true])
        XCTAssertEqual(stats.exerciseRows.map(\.isOptional), [false, false], "It is not the optional sample.")
        XCTAssertEqual(stats.exerciseRows.last?.name, "Easier: \(easier.displayName)")
        XCTAssertEqual(stats.exerciseRows.last?.summary, "Easier: \(easier.displayName) — 1 set · 3 reps")
        XCTAssertEqual(stats.exerciseCount, 1, "The easier version replaces the item; it isn't one more exercise.")
        XCTAssertEqual(stats.totalSets, 2)
        XCTAssertEqual(stats.totalReps, 8)
    }

    func testAnEasierVersionLeftPartwayKeepsItsWorkWithNoOutcome() throws {
        let main = hold(seconds: 20)
        let recorder = TooHardRecorder()
        recorder.option = EasierSwapOption(target: RungDose(variant: shallow, dose: .seconds(10)), exerciseID: main.id,
                                           reducedRange: false)
        let harness = makeHarness(exercises: [main], launch: launch(exercise: main, dose: .seconds(20)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.scheduler.advance(by: 6)
        harness.model.send(.tooHard)
        harness.model.takeEasierVersion()
        harness.model.send(.start)
        harness.scheduler.advance(by: 4)

        harness.model.send(.nextExercise)

        let record = try savedRecord(harness)
        XCTAssertEqual(record.entries.map(\.name), [main.displayName, "Easier: \(main.displayName)"])
        let swapEntry = try XCTUnwrap(record.entries.last)
        XCTAssertEqual(swapEntry.sets.map(\.seconds), [4], "The seconds held are saved.")
        XCTAssertNil(swapEntry.outcome, "Never labeled skipped.")
        XCTAssertEqual(record.entries.first?.sets.map(\.seconds), [6])
        let swapCard = try XCTUnwrap(harness.model.effortCard)
        XCTAssertEqual(swapCard.amount, 4)
        XCTAssertEqual(swapCard.setCount, 1, "The four seconds are counted once.")
    }

    func testAnotherRoundDropsTheEasierVersion() throws {
        let main = selfReported(target: 5)
        let recorder = TooHardRecorder()
        recorder.option = EasierSwapOption(target: RungDose(variant: shallow, dose: .reps(3)), exerciseID: main.id,
                                           reducedRange: false)
        let harness = makeHarness(exercises: [main], launch: launch(exercise: main, dose: .reps(5)), recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.tooHard)
        harness.model.takeEasierVersion()
        harness.model.send(.start)
        harness.model.send(.nextSet)
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete)

        harness.model.send(.anotherRound)

        XCTAssertEqual(harness.model.session.plan?.items.map(\.isEasierSwap), [false],
                       "A new round starts from what was prescribed.")
    }

    // MARK: - Tracking loss is not Too Hard

    func testTrackingLostThenTooHardKeepsTheTrackerLostAndTheConfirmationFollowsTheCard() throws {
        // Revert check (c): letting Too hard overwrite the tracker's status makes this fail.
        let wallPushUp = WallPushUpExercise.definition()
        let recorder = TooHardRecorder()
        let harness = makeHarness(exercises: [wallPushUp], launch: launch(exercise: wallPushUp, dose: .reps(3)),
                                  recorder: recorder)
        open(harness)
        var time = 0.0
        beginCameraSet(harness, exercise: wallPushUp, time: &time)
        loseTracking(harness, time: &time)
        XCTAssertFalse(harness.model.session.framing.isReliable)

        harness.model.send(.tooHard)

        XCTAssertFalse(harness.model.session.framing.isReliable, "Flagging doesn't touch what tracking says.")
        XCTAssertNotNil(harness.model.tooHardOffer)
        harness.model.stopHere()
        let card = try XCTUnwrap(harness.model.effortCard)
        XCTAssertEqual(card.preselected, .tooHard)
        XCTAssertEqual(card.amount, 0, "The tracker counted nothing.")
        harness.model.rateEffort(.tooHard)

        let unchanged = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(unchanged.tracker.status, .lost, "The tracker status stays lost.")
        XCTAssertEqual(unchanged.tracker.observed, .reps(0))
        XCTAssertEqual(unchanged.confirmation, .none, "Nobody vouched for an amount: not the tracker, not the card.")
        XCTAssertNil(unchanged.confirmed)
        XCTAssertEqual(unchanged.effort, .tooHard, "The user's own answer is the rating.")
        XCTAssertTrue(unchanged.midSetTooHard)
    }

    func testTrackingLostThenTooHardThenACorrectedAmountIsRecordedAsTheUsersWordWithTheTrackerStillLost() throws {
        let wallPushUp = WallPushUpExercise.definition()
        let recorder = TooHardRecorder()
        let harness = makeHarness(exercises: [wallPushUp], launch: launch(exercise: wallPushUp, dose: .reps(3)),
                                  recorder: recorder)
        open(harness)
        var time = 0.0
        beginCameraSet(harness, exercise: wallPushUp, time: &time)
        loseTracking(harness, time: &time)
        harness.model.send(.tooHard)
        harness.model.stopHere()

        harness.model.adjustEffortAmount(by: 2)
        harness.model.rateEffort(.tooHard)

        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(evidence.tracker.status, .lost)
        XCTAssertEqual(evidence.tracker.observed, .reps(0))
        XCTAssertEqual(evidence.confirmation, .user)
        XCTAssertEqual(evidence.confirmed, .reps(2), "The confirmation follows the card.")
        XCTAssertEqual(evidence.completion, .stoppedEarly)
    }

    func testTrackingLossAloneIsNeverATooHard() throws {
        let wallPushUp = WallPushUpExercise.definition()
        let recorder = TooHardRecorder()
        let harness = makeHarness(exercises: [wallPushUp], launch: launch(exercise: wallPushUp, dose: .reps(3)),
                                  recorder: recorder)
        open(harness)
        var time = 0.0
        beginCameraSet(harness, exercise: wallPushUp, time: &time)
        loseTracking(harness, time: &time)

        harness.model.send(.nextSet)
        harness.model.rateEffort(.okay)

        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertNil(harness.model.tooHardOffer)
        XCTAssertFalse(evidence.midSetTooHard, "Losing the camera never flags an item.")
        XCTAssertEqual(evidence.tracker.status, .lost)
        XCTAssertEqual(evidence.effort, .okay)
    }

    // MARK: - Voice

    func testTooHardAnswersTheCardWhenItIsOpenAndOtherwiseIsTheCommand() {
        let open = makeVoiceRig()
        open.controller.acceptsEffortFeedback = true
        open.recognizer.hear("too hard", final: true)
        XCTAssertEqual(open.efforts, [.tooHard], "With the card open, \"too hard\" is an effort answer.")
        XCTAssertTrue(open.commands.isEmpty)

        let closed = makeVoiceRig()
        closed.recognizer.hear("too hard", final: true)
        XCTAssertEqual(closed.commands, [.tooHard], "With no card open, it is the Too hard command.")
        XCTAssertTrue(closed.efforts.isEmpty)
    }

    func testEveryTooHardPhraseIsTheCommandAndTheOtherCommandsAreUnchanged() {
        let rig = makeVoiceRig()
        for phrase in ["too hard", "this is too hard", "too difficult", "it's too hard"] {
            rig.recognizer.hear(phrase, final: true)
        }
        XCTAssertEqual(rig.commands, [.tooHard, .tooHard, .tooHard, .tooHard])

        let parser = VoiceCommandParser(exercises: ExerciseCatalog.all)
        XCTAssertEqual(parser.parse("next set")?.command, .nextSet)
        XCTAssertEqual(parser.parse("pause")?.command, .pause)
        XCTAssertEqual(parser.parse("end workout")?.command, .endWorkout)
        XCTAssertEqual(parser.parse("how many reps")?.command, .repCount)
        XCTAssertNil(parser.parse("hard"))
    }

    func testANegatedTooHardIsNeverTheCommand() {
        let parser = VoiceCommandParser(exercises: ExerciseCatalog.all)
        for phrase in ["not too hard", "it's not too hard", "this isn't too hard", "that wasn't too hard",
                       "never too hard", "no it's not too hard"] {
            XCTAssertNil(parser.parse(phrase), "\"\(phrase)\" says the opposite.")
        }
        XCTAssertEqual(parser.parse("this is too hard")?.command, .tooHard)

        let rig = makeVoiceRig()
        rig.recognizer.hear("not too hard", final: true)
        XCTAssertTrue(rig.commands.isEmpty, "Nothing is flagged by a negation.")
    }

    func testTooHardMatchesOnlyTheAffirmativeAliasPlusPoliteFillers() {
        let parser = VoiceCommandParser(exercises: ExerciseCatalog.all)
        for phrase in ["too hard", "Too hard!", "okay this is too hard", "please, too difficult", "yeah it's too hard coach",
                       "um too hard really"] {
            XCTAssertEqual(parser.parse(phrase)?.command, .tooHard, phrase)
        }
        // Any other word makes it something else, which the normal commands then see.
        XCTAssertNil(parser.parse("too hard right now"))
        XCTAssertNil(parser.parse("this is too hard but I can do it"))
        XCTAssertNil(parser.parse("it is too hard"))
    }

    func testTooHardNeverSwallowsTheCommandSaidWithIt() {
        // Revert check (finding 2): matching the alias among arbitrary words makes these Too hard.
        let parser = VoiceCommandParser(exercises: ExerciseCatalog.all)
        XCTAssertEqual(parser.parse("this is too hard, pause")?.command, .pause)
        XCTAssertEqual(parser.parse("too hard pause")?.command, .pause)
        XCTAssertEqual(parser.parse("pause this is too hard")?.command, .pause)
        XCTAssertEqual(parser.parse("too hard, next set")?.command, .nextSet)
        XCTAssertEqual(parser.parse("too hard end workout")?.command, .endWorkout)
        XCTAssertEqual(parser.parse("too difficult stop")?.command, .pause)
        XCTAssertEqual(parser.parse("pause")?.command, .pause, "The same command alone is unchanged.")

        let rig = makeVoiceRig()
        rig.recognizer.hear("this is too hard, pause", final: true)
        XCTAssertEqual(rig.commands, [.pause], "A final mixed utterance pauses and flags nothing.")
    }

    func testAStreamingMixedUtteranceNeverFlagsBeforeItsCommandArrives() {
        let rig = makeVoiceRig()
        rig.recognizer.hear("this is too hard", final: false)
        XCTAssertTrue(rig.commands.isEmpty, "A partial Too hard waits: a command may still follow.")
        rig.advance(0.3)
        rig.recognizer.hear("this is too hard pause", final: false)
        XCTAssertEqual(rig.commands, [.pause], "The command that followed wins at once.")
        rig.advance(3)
        XCTAssertEqual(rig.commands, [.pause], "And the earlier partial never fires afterwards.")

        let alone = makeVoiceRig()
        alone.recognizer.hear("this is too hard", final: false)
        alone.advance(0.3)
        XCTAssertTrue(alone.commands.isEmpty, "Not settled yet.")
        alone.advance(0.5)
        XCTAssertEqual(alone.commands, [.tooHard], "Said alone, it settles and runs once.")
        alone.advance(3)
        XCTAssertEqual(alone.commands, [.tooHard])

        let final = makeVoiceRig()
        final.recognizer.hear("too hard", final: true)
        XCTAssertEqual(final.commands, [.tooHard], "A final transcript doesn't wait.")
    }

    func testEveryAdvertisedPhraseWorksWithTheCardOpenAndClosed() throws {
        // Revert check (finding 4): an alias missing from the effort parser reaches the model as an ignored command.
        let advertised = ["too hard", "this is too hard", "too difficult", "it's too hard"]
        XCTAssertEqual(TooHardPhrases.aliases, advertised)
        let sets = try XCTUnwrap(VoiceCommandHelp.sections(exercises: ExerciseCatalog.all).first { $0.title == "Sets" })
        let entry = try XCTUnwrap(sets.entries.first { $0.command == .tooHard })
        XCTAssertEqual([entry.title.lowercased()] + entry.alternates, advertised, "Help lists exactly these.")

        for phrase in advertised {
            let open = makeVoiceRig()
            open.controller.acceptsEffortFeedback = true
            open.recognizer.hear(phrase, final: true)
            XCTAssertEqual(open.efforts, [.tooHard], "\"\(phrase)\" answers an open card.")
            XCTAssertTrue(open.commands.isEmpty, "\"\(phrase)\" is not also a command.")
            XCTAssertEqual(EffortPhraseParser.parse(phrase)?.effort, .tooHard)

            let closed = makeVoiceRig()
            closed.recognizer.hear(phrase, final: true)
            XCTAssertEqual(closed.commands, [.tooHard], "\"\(phrase)\" opens the offer when no card is open.")
            XCTAssertTrue(closed.efforts.isEmpty)
        }
    }

    func testEveryAdvertisedPhraseOpensTheOfferInASetAndRatesTheOpenCardThroughTheModel() throws {
        for phrase in TooHardPhrases.aliases {
            let exercise = selfReported(target: 5)
            let recorder = TooHardRecorder()
            let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                      recorder: recorder)
            open(harness)
            harness.model.send(.start)
            XCTAssertNotNil(VoiceCommandParser(exercises: [exercise]).parse(phrase), phrase)
            harness.voice.emit(try XCTUnwrap(VoiceCommandParser(exercises: [exercise]).parse(phrase)?.command))
            XCTAssertNotNil(harness.model.tooHardOffer, "\"\(phrase)\" during a set opens the offer.")

            harness.model.send(.nextSet)
            XCTAssertNotNil(harness.model.effortCard)
            let match = try XCTUnwrap(EffortPhraseParser.parse(phrase), phrase)
            harness.voice.emitEffort(match.effort)
            XCTAssertEqual(recorder.evidence.first?.effort, .tooHard, "\"\(phrase)\" answers the open card.")
            XCTAssertEqual(recorder.evidence.first?.midSetTooHard, true)
        }
    }

    func testTheHelpListsTooHardWithItsPhrases() throws {
        let sets = try XCTUnwrap(VoiceCommandHelp.sections(exercises: ExerciseCatalog.all).first { $0.title == "Sets" })
        let entry = try XCTUnwrap(sets.entries.first { $0.command == .tooHard })
        XCTAssertEqual(entry.title, "Too hard")
        XCTAssertEqual(entry.alternates, ["this is too hard", "too difficult", "it's too hard"])
        XCTAssertFalse(entry.isDestructive)
    }

    // MARK: - The reducer

    func testTheReducerIgnoresTheTooHardCommand() {
        var session = makeSession()
        _ = session.handle(.command(.start), at: 2)
        let before = session

        let effects = session.handle(.command(.tooHard), at: 3)

        XCTAssertTrue(effects.isEmpty)
        XCTAssertEqual(session.phase, before.phase)
        XCTAssertEqual(session.isCounting, before.isCounting)
        XCTAssertEqual(session.progress, before.progress)
    }

    func testTheReducerInsertsAnEasierSwapRightAfterTheEndedItemAndSetsItUp() throws {
        var session = makeSession(withSample: true)
        _ = session.handle(.command(.start), at: 2)
        _ = session.handle(.command(.nextSet), at: 3)
        XCTAssertEqual(session.phase, .resting)

        let effects = session.handle(.startEasierSwap(swapRequest()), at: 4)

        XCTAssertFalse(effects.isEmpty)
        let items = try XCTUnwrap(session.plan?.items)
        XCTAssertEqual(items.map(\.id), [mainID, swapID, sampleID])
        XCTAssertEqual(items.map(\.isEasierSwap), [false, true, false])
        let swap = try XCTUnwrap(items.dropFirst().first)
        XCTAssertEqual(swap.exerciseID, .wallPushUp)
        XCTAssertTrue(swap.reducedRange)
        XCTAssertEqual(swap.targetReps, 1...1)
        XCTAssertEqual(session.currentPlanItem?.id, swapID)
        XCTAssertEqual(session.phase, .ready)
        XCTAssertNil(session.restEndsAt, "No rest before the easier version.")
        XCTAssertEqual(swap.label(for: ExerciseCatalog.definition(for: .wallPushUp)), "Easier: Shallow Wall Push-Up")
        XCTAssertEqual(session.planPositionLabel, "Easier version")
    }

    func testTheReducerNumbersOnlyThePrescribedItems() throws {
        var session = makeSession(withSample: true)
        _ = session.handle(.command(.start), at: 2)
        _ = session.handle(.command(.nextSet), at: 3)
        _ = session.handle(.startEasierSwap(swapRequest()), at: 4)
        _ = session.handle(.command(.start), at: 5)
        _ = session.handle(.command(.nextSet), at: 6)
        XCTAssertEqual(session.currentPlanItem?.id, sampleID)

        XCTAssertEqual(session.planPositionLabel, "Exercise 2 of 2", "The main item and the sample; not the swap.")
    }

    func testTheReducerAcceptsASwapAfterASkippedItemTooAndAtTheEndOfThePlan() throws {
        // A multi-set item ends by skipping its remaining sets; the last item ends the plan.
        var session = makeSession(withSample: false, mainSets: 2)
        _ = session.handle(.command(.start), at: 2)
        _ = session.handle(.command(.nextSet), at: 3)
        _ = session.handle(.command(.nextExercise), at: 4)
        XCTAssertEqual(session.planRecords[mainID]?.outcome, .skipped)
        XCTAssertEqual(session.phase, .exerciseComplete)

        _ = session.handle(.startEasierSwap(swapRequest()), at: 5)

        XCTAssertEqual(session.plan?.items.map(\.isEasierSwap), [false, true])
        XCTAssertEqual(session.currentPlanItem?.id, swapID)
        XCTAssertEqual(session.phase, .ready)
    }

    func testTheReducerRefusesASwapItCannotRun() {
        var base = makeSession(withSample: true)
        _ = base.handle(.command(.start), at: 2)

        // The item is still in progress, so nothing has ended.
        var running = base
        _ = running.handle(.startEasierSwap(swapRequest()), at: 3)
        XCTAssertEqual(running.plan?.items.count, 2)

        _ = base.handle(.command(.nextSet), at: 3)

        func refused(_ request: EasierSwapRequest, in session: WorkoutSession) -> Bool {
            var copy = session
            _ = copy.handle(.startEasierSwap(request), at: 4)
            return copy.plan?.items.count == session.plan?.items.count
        }
        XCTAssertTrue(refused(swapRequest(after: TooHardOfferTests.uuid(0x7F)), in: base), "An unknown item.")
        XCTAssertTrue(refused(swapRequest(amount: 0), in: base), "Nothing to do.")
        XCTAssertTrue(refused(swapRequest(exercise: ExerciseID(rawValue: "no_such_exercise")), in: base),
                      "An exercise the coach doesn't have.")
        XCTAssertFalse(refused(swapRequest(), in: base), "The ended item with a rest before the sample is fine.")

        var taken = base
        _ = taken.handle(.startEasierSwap(swapRequest()), at: 4)
        XCTAssertTrue(refused(swapRequest(itemID: TooHardOfferTests.uuid(0x7E)), in: taken), "Only one swap per item.")
        XCTAssertTrue(refused(swapRequest(itemID: TooHardOfferTests.uuid(0x7D), after: swapID), in: taken),
                      "An easier version isn't swapped again.")

        var started = taken
        _ = started.handle(.command(.start), at: 5)
        XCTAssertTrue(refused(swapRequest(itemID: TooHardOfferTests.uuid(0x7C)), in: started), "Already running.")
    }

    func testTheReducerNeverTakesASwapOutsideAPlan() {
        var session = WorkoutSession(exercises: ExerciseCatalog.all, initialExercise: .wallPushUp)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: 1)
        _ = session.handle(.command(.start), at: 2)
        _ = session.handle(.command(.nextSet), at: 3)

        _ = session.handle(.startEasierSwap(swapRequest()), at: 4)

        XCTAssertNil(session.plan)
    }

    // MARK: - The adapter

    func testTheChoiceFlagsTheEvidenceAndNeverTouchesTheTrackerOrTheRating() {
        let identity = adaptiveIdentity()
        for tracking in [FinishedWorkoutItem.Tracking.camera, .selfReported, .timedHold] {
            for lost in [false, true] {
                let item = finished(amounts: [2], target: 5, result: .completed, tracking: tracking, trackingLost: lost)
                let plain = WorkoutOutcomeAdapter.evidence(
                    id: TooHardOfferTests.uuid(0x71), recordedAt: Date(timeIntervalSince1970: 1_000), workoutID: nil,
                    identity: identity, item: item, answer: .init(effort: .okay, amount: 2, isAdjusted: false))
                XCTAssertFalse(plain.midSetTooHard)
                for choice in [WorkoutOutcomeAdapter.TooHardChoice.flagged, .stoppedHere, .switchedToEasier] {
                    let chosen = WorkoutOutcomeAdapter.evidence(
                        id: TooHardOfferTests.uuid(0x71), recordedAt: Date(timeIntervalSince1970: 1_000), workoutID: nil,
                        identity: identity, item: item, answer: .init(effort: .okay, amount: 2, isAdjusted: false),
                        tooHard: choice)
                    XCTAssertTrue(chosen.midSetTooHard)
                    XCTAssertEqual(chosen.tracker, plain.tracker, "\(tracking) lost=\(lost) \(choice)")
                    XCTAssertEqual(chosen.confirmation, plain.confirmation, "\(tracking) lost=\(lost) \(choice)")
                    XCTAssertEqual(chosen.confirmed, plain.confirmed)
                    XCTAssertEqual(chosen.effort, .okay)
                }
            }
        }
    }

    func testTheChoiceNeverSetsARatingByItself() {
        let item = finished(amounts: [2], target: 5, result: .completed)
        for choice in [WorkoutOutcomeAdapter.TooHardChoice.flagged, .stoppedHere, .switchedToEasier] {
            let evidence = WorkoutOutcomeAdapter.evidence(
                id: TooHardOfferTests.uuid(0x72), recordedAt: Date(timeIntervalSince1970: 1_000), workoutID: nil,
                identity: adaptiveIdentity(), item: item, answer: nil, tooHard: choice)
            XCTAssertNil(evidence.effort)
            XCTAssertTrue(evidence.midSetTooHard)
        }
    }

    func testCompletionAfterAChoiceOnBothSidesOfTheBoundaries() {
        let after = WorkoutOutcomeAdapter.completionAfter
        XCTAssertEqual(after(.completed, nil), .completed)
        XCTAssertEqual(after(.completed, .flagged), .completed)
        XCTAssertEqual(after(.completed, .stoppedHere), .stoppedEarly, "Stopping is the user's own reason.")
        XCTAssertEqual(after(.stoppedEarly, .stoppedHere), .stoppedEarly)
        XCTAssertEqual(after(.endedWorkout, .stoppedHere), .endedWorkout)
        XCTAssertEqual(after(.notAttempted, .stoppedHere), .notAttempted)
        XCTAssertEqual(after(.completed, .switchedToEasier), .switchedToEasier)
        XCTAssertEqual(after(.stoppedEarly, .switchedToEasier), .switchedToEasier)
        XCTAssertEqual(after(.notAttempted, .switchedToEasier), .switchedToEasier)
    }

    func testNoBonusIsOfferedToSomeoneWhoSaidItWasTooHard() {
        let identity = WorkoutOutcomeAdapter.Identity(
            origin: .adaptive(prescriptionID: prescriptionID, itemID: mainID, prescribed: .reps(5)),
            family: .push, variant: wall, offersBonus: true)
        let item = finished(amounts: [5], target: 5, result: .completed)
        let easy = WorkoutOutcomeAdapter.Answer(effort: .easy, amount: 5, isAdjusted: false)

        XCTAssertEqual(WorkoutOutcomeAdapter.bonusOffer(identity: identity, item: item, answer: easy), .reps(1))
        for choice in [WorkoutOutcomeAdapter.TooHardChoice.flagged, .stoppedHere, .switchedToEasier] {
            XCTAssertNil(WorkoutOutcomeAdapter.bonusOffer(identity: identity, item: item, answer: easy, tooHard: choice))
        }
    }

    // MARK: - Recording

    func testARecordingWritesTheTooHardCommandTheSwapInputAndTheSwapPlanItem() throws {
        let main = selfReported(target: 5)
        let store = MemoryWorkoutRecordingStore()
        let recorder = WorkoutSessionRecorder(store: store)
        let evidence = TooHardRecorder()
        evidence.option = EasierSwapOption(target: RungDose(variant: shallow, dose: .reps(3)), exerciseID: main.id,
                                           reducedRange: false)
        let launch = launch(exercise: main, dose: .reps(5))
        let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), exercises: [main],
                                               initialExercise: main.id, recorder: recorder, plan: launch.plan,
                                               adaptive: evidence, todayLaunch: launch)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.tooHard)

        harness.model.takeEasierVersion()

        let text = store.writer(for: recorder.id).lines.joined(separator: "\n")
        XCTAssertTrue(text.contains(#""command":"tooHard""#), "The Too hard command is in the recording.")
        XCTAssertTrue(text.contains(#""type":"easierSwap""#), "The input that inserted the easier version is too.")
        XCTAssertTrue(text.contains(#""after":"\#(mainID.uuidString)""#))
        XCTAssertTrue(text.contains(#""exercise":"\#(main.id.rawValue)""#))
        XCTAssertFalse(text.contains(#""easierSwap":true"#), "The header's plan was written before any swap existed.")

        let swapPlan = WorkoutPlan(id: nil, name: "Plan", items: [
            WorkoutPlanItem(id: mainID, exerciseID: main.id, sets: 1, targetReps: 5...5),
            WorkoutPlanItem(id: swapID, exerciseID: main.id, sets: 1, targetReps: 3...3, isEasierSwap: true)
        ])
        let secondStore = MemoryWorkoutRecordingStore()
        let secondRecorder = WorkoutSessionRecorder(store: secondStore)
        let second = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), exercises: [main],
                                              initialExercise: main.id, recorder: secondRecorder, plan: swapPlan)
        open(second)
        let secondText = secondStore.writer(for: secondRecorder.id).lines.joined(separator: "\n")
        XCTAssertEqual(secondText.components(separatedBy: #""easierSwap":true"#).count - 1, 1,
                       "Only the easier version's plan item says so.")
    }

    // MARK: - The real engine

    func testTakingTheEasierVersionThroughTheRealEngineSavesItsPrescriptionAndReplaysTheEvidence() throws {
        let wallPushUp = WallPushUpExercise.definition()
        let shallowExercise = try XCTUnwrap(wallPushUp.reducedRange?())
        let rig = makeEngineRig(facts: AdaptiveFacts(calibrations: [calibration(.push, at: wall, dose: .reps(1))]))
        let launch = try XCTUnwrap(rig.coordinator.start(asOf: Date(timeIntervalSince1970: 900)))
        let mainItem = try XCTUnwrap(launch.prescription.items.first)
        let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), exercises: [wallPushUp],
                                               initialExercise: wallPushUp.id, plan: launch.plan,
                                               adaptive: rig.coordinator, todayLaunch: launch)
        open(harness)
        var time = 0.0
        beginCameraSet(harness, exercise: wallPushUp, time: &time)
        harness.model.send(.tooHard)
        let offer = try XCTUnwrap(harness.model.tooHardOffer)
        // What the offer shows is exactly what the engine says.
        let enginesAnswer = try XCTUnwrap(try rig.engine.easierSwap(for: mainItem, asOf: Date(timeIntervalSince1970: 1_000)))
        XCTAssertEqual(enginesAnswer, RungDose(variant: shallow, dose: .reps(1)))
        XCTAssertEqual(offer.easierVersion?.name, shallowExercise.displayName)
        XCTAssertEqual(offer.easierVersion?.amountLabel, "1 rep")

        harness.model.takeEasierVersion()

        let prescriptions = try rig.store.loadFacts().prescriptions
        XCTAssertEqual(prescriptions.count, 2, "Today's prescription and the easier version's.")
        let swapPrescription = try XCTUnwrap(prescriptions.first { $0.items.contains { $0.role == .easierSwap } })
        XCTAssertEqual(swapPrescription.kind, .todaySession)
        XCTAssertEqual(swapPrescription.items.map(\.target), [enginesAnswer])
        XCTAssertEqual(swapPrescription.items.map(\.family), [.push])
        XCTAssertEqual(harness.model.session.plan?.items.last?.id, swapPrescription.items.first?.id)

        driveCameraSet(harness, exercise: shallowExercise, time: &time)
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete)
        harness.model.rateEffort(.okay)

        let facts = try rig.store.loadFacts()
        XCTAssertEqual(facts.evidence.count, 2)
        let mainEvidence = try XCTUnwrap(facts.evidence.first { $0.prescriptionItemID == mainItem.id })
        let swapEvidence = try XCTUnwrap(facts.evidence.first { $0.prescriptionItemID == swapPrescription.items.first?.id })
        XCTAssertEqual(mainEvidence.completion, .switchedToEasier)
        XCTAssertEqual(mainEvidence.effort, .tooHard)
        XCTAssertTrue(mainEvidence.midSetTooHard)
        XCTAssertEqual(swapEvidence.prescriptionID, swapPrescription.id)
        XCTAssertEqual(swapEvidence.variant, shallow)
        XCTAssertEqual(swapEvidence.effort, .okay)

        let profile = try rig.engine.profile()
        XCTAssertEqual(profile.state(.push)?.current, enginesAnswer, "Too Hard on the main item moved it down.")
        XCTAssertTrue(profile.transitions.contains { $0.rationale.codes.contains(.easierSwapRecorded) },
                      "The swap's own evidence replays as the easier swap rule says.")
        XCTAssertTrue(profile.transitions.contains { $0.rationale.codes.contains(.tooHardEasierRung) })
        // The main item switched to the easier version counts as today's main item done.
        if case .completedToday(let family, _) = rig.coordinator.status(asOf: Date(timeIntervalSince1970: 1_100)) {
            XCTAssertEqual(family, .push)
        } else {
            XCTFail("A main item switched to the easier version is today's main item done.")
        }
    }

    // MARK: - Helpers

    private static func uuid(_ number: Int) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, UInt8(truncatingIfNeeded: number)))
    }

    private func selfReported(target: Int, sets: Int = 1) -> ExerciseDefinition {
        selfReported(from: ShoulderPressExercise.definition(), target: target, sets: sets)
    }

    private func selfReported(from base: ExerciseDefinition, target: Int, sets: Int = 1) -> ExerciseDefinition {
        var copy = base
        copy.tracking = .selfReported
        copy.targetReps = target...target
        copy.autoCompleteReps = target
        copy.targetRangeAnnouncementReps = nil
        copy.sets = sets
        return copy
    }

    private func hold(seconds: Int) -> ExerciseDefinition {
        var copy = selfReported(target: seconds)
        copy.doseUnit = .seconds
        return copy
    }

    /// Today's Session as the coordinator would prepare it.
    private func launch(exercise: ExerciseDefinition, dose: Dose, withSample: Bool = false) -> TodaySessionLaunch {
        var items = [AdaptivePlanItem(itemID: mainID, role: .main, family: .push,
                                      rungDose: RungDose(variant: wall, dose: dose), exerciseID: exercise.id,
                                      reducedRange: false)]
        if withSample {
            items.append(AdaptivePlanItem(itemID: sampleID, role: .harderSample, family: .push,
                                          rungDose: RungDose(variant: wall, dose: .reps(1)), exerciseID: exercise.id,
                                          reducedRange: false))
        }
        let planItems = items.map { item in
            WorkoutPlanItem(id: item.itemID, exerciseID: item.exerciseID, sets: 1,
                            targetReps: item.rungDose.dose.amount...item.rungDose.dose.amount,
                            reducedRange: item.reducedRange, isOptional: item.role == .harderSample)
        }
        let prescription = Prescription(
            id: prescriptionID, issuedAt: Date(timeIntervalSince1970: 900), kind: .todaySession, policyVersion: .v1,
            catalogVersion: "test",
            items: items.map { PrescriptionItem(id: $0.itemID, family: $0.family, target: $0.rungDose, role: $0.role,
                                                offersBonus: true) },
            rationale: "Test")
        return TodaySessionLaunch(prescription: prescription,
                                  plan: WorkoutPlan(id: AdaptiveTrainingCoordinator.todaySessionPlanID,
                                                    name: "Today's Session", items: planItems),
                                  items: items)
    }

    private func makeHarness(exercises: [ExerciseDefinition], launch: TodaySessionLaunch?, plan: WorkoutPlan? = nil,
                             recorder: TooHardRecorder) -> WorkoutCoachHarness {
        WorkoutCoachHarness.make(preferences: InMemoryPreferences(), exercises: exercises,
                                 initialExercise: exercises.first?.id ?? .shoulderPress,
                                 plan: launch?.plan ?? plan, adaptive: recorder, todayLaunch: launch)
    }

    private func open(_ harness: WorkoutCoachHarness) {
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
    }

    /// One frame of the guide's own demonstration at the camera's real cadence.
    private func frame(_ harness: WorkoutCoachHarness, exercise: ExerciseDefinition, time: inout Double) {
        harness.scheduler.advance(by: 0.1)
        time += 0.1
        harness.camera.emit(.frame(ReadyPoseFixtures.demoFrame(exercise, motionTime: time, at: time)))
    }

    /// Frames until the set is under way.
    private func beginCameraSet(_ harness: WorkoutCoachHarness, exercise: ExerciseDefinition, time: inout Double) {
        for _ in 0..<10 { frame(harness, exercise: exercise, time: &time) }
        if harness.model.session.phase != .exercising { harness.model.send(.start) }
    }

    /// Frames until the set ends.
    private func finishCameraSet(_ harness: WorkoutCoachHarness, exercise: ExerciseDefinition, time: inout Double) {
        var steps = 0
        while harness.model.session.phase == .exercising, steps < 600 {
            frame(harness, exercise: exercise, time: &time)
            steps += 1
        }
    }

    private func driveCameraSet(_ harness: WorkoutCoachHarness, exercise: ExerciseDefinition, time: inout Double) {
        beginCameraSet(harness, exercise: exercise, time: &time)
        finishCameraSet(harness, exercise: exercise, time: &time)
    }

    /// Frames until the camera has counted `reps`, with the set still under way.
    private func driveCameraUntilReps(_ reps: Int, _ harness: WorkoutCoachHarness, exercise: ExerciseDefinition,
                                      time: inout Double) {
        var steps = 0
        while harness.model.session.phase == .exercising, harness.model.session.repCount < reps, steps < 600 {
            frame(harness, exercise: exercise, time: &time)
            steps += 1
        }
    }

    /// Frames with nobody in them, so the camera reports the body lost.
    private func loseTracking(_ harness: WorkoutCoachHarness, time: inout Double) {
        for _ in 0..<3 {
            harness.scheduler.advance(by: 0.1)
            time += 0.1
            harness.camera.emit(.frame(PoseFrame(pose: BodyPose(landmarks: [:], imageWidth: 1080, imageHeight: 1920),
                                                 timestamp: time)))
        }
    }

    private func savedRecord(_ harness: WorkoutCoachHarness) throws -> WorkoutRecord {
        try XCTUnwrap(WorkoutRecord(session: harness.model.session, startedAt: Date(timeIntervalSince1970: 0),
                                    endedAt: Date(timeIntervalSince1970: 30), id: harness.model.workoutID))
    }

    /// Today's Session of a wall push-up main item (and optionally the harder sample), driven through the reducer alone.
    private func makeSession(withSample: Bool = false, mainSets: Int = 1) -> WorkoutSession {
        var items = [WorkoutPlanItem(id: mainID, exerciseID: .wallPushUp, sets: mainSets, targetReps: 3...3)]
        if withSample {
            items.append(WorkoutPlanItem(id: sampleID, exerciseID: .wallPushUp, sets: 1, targetReps: 1...1, isOptional: true))
        }
        let plan = WorkoutPlan(id: AdaptiveTrainingCoordinator.todaySessionPlanID, name: "Today's Session", items: items)
        var session = WorkoutSession(exercises: ExerciseCatalog.all, initialExercise: .wallPushUp, plan: plan)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: 1)
        return session
    }

    private func swapRequest(itemID: UUID? = nil, after: UUID? = nil, exercise: ExerciseID = .wallPushUp,
                             amount: Int = 1) -> EasierSwapRequest {
        EasierSwapRequest(itemID: itemID ?? swapID, after: after ?? mainID, exerciseID: exercise, reducedRange: true,
                          amount: amount)
    }

    private func adaptiveIdentity() -> WorkoutOutcomeAdapter.Identity {
        WorkoutOutcomeAdapter.Identity(
            origin: .adaptive(prescriptionID: prescriptionID, itemID: mainID, prescribed: .reps(5)),
            family: .push, variant: wall)
    }

    private func finished(amounts: [Int], target: Int, result: FinishedWorkoutItem.Result,
                          tracking: FinishedWorkoutItem.Tracking = .selfReported,
                          trackingLost: Bool = false) -> FinishedWorkoutItem {
        FinishedWorkoutItem(planItemID: mainID, exerciseID: .wallPushUp, reducedRange: false,
                            unit: tracking == .timedHold ? .seconds : .reps, tracking: tracking, setAmounts: amounts,
                            target: target, result: result, trackingLost: trackingLost)
    }

    // MARK: - Engine rig

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    /// A starting point committed before the workout's evidence, which the harness stamps at t = 1000 s.
    private func calibration(_ family: MovementFamilyID, at variant: VariantID, dose: Dose) -> CalibrationSessionRecord {
        CalibrationSessionRecord(id: TooHardOfferTests.uuid(0xCA), kind: .initial,
                                 startedAt: Date(timeIntervalSince1970: 100), endedAt: Date(timeIntervalSince1970: 100),
                                 status: .committed, families: [family],
                                 startingPoints: [CalibrationStart(family: family, start: RungDose(variant: variant, dose: dose))])
    }

    private struct EngineRig {
        let store: InMemoryAdaptiveTrainingStore
        let engine: AdaptiveTrainingEngine
        let coordinator: AdaptiveTrainingCoordinator
    }

    private func makeEngineRig(facts: AdaptiveFacts) -> EngineRig {
        let store = InMemoryAdaptiveTrainingStore(facts: facts)
        let bridge = ExerciseVariantBridge(exercises: LiveExerciseCatalog(), ladders: .v1)
        let engine = AdaptiveTrainingEngine(store: store, builtExerciseIDs: bridge.availability(equipment: []).builtExerciseIDs,
                                            calendar: calendar, catalog: .v1)
        return EngineRig(store: store, engine: engine, coordinator: AdaptiveTrainingCoordinator(engine: engine, bridge: bridge))
    }

    // MARK: - Voice rig

    @MainActor
    private struct VoiceRig {
        let controller: WorkoutVoiceController
        let recognizer: TooHardScriptedRecognizer
        let scheduler: ManualScheduler
        let box: VoiceBox

        var efforts: [EffortFeedback] { box.efforts }
        var commands: [WorkoutCommand] { box.commands }

        /// Time passes, so a transcript can settle.
        func advance(_ seconds: TimeInterval) { scheduler.advance(by: seconds) }
    }

    private final class VoiceBox {
        var efforts: [EffortFeedback] = []
        var commands: [WorkoutCommand] = []
    }

    /// The real controller with the real command parser, so the actual phrases are tested.
    private func makeVoiceRig() -> VoiceRig {
        let recognizer = TooHardScriptedRecognizer()
        let clock = ManualClock(now: 10)
        let scheduler = ManualScheduler(clock: clock)
        let controller = WorkoutVoiceController(recognizer: recognizer,
                                                parser: VoiceCommandParser(exercises: ExerciseCatalog.all),
                                                permissions: TooHardGrantedPermissions(), audio: FakeAudioSession(),
                                                clock: { clock.now }, scheduler: scheduler)
        let box = VoiceBox()
        controller.onEffort = { box.efforts.append($0) }
        controller.onCommand = { box.commands.append($0) }
        controller.enable()
        return VoiceRig(controller: controller, recognizer: recognizer, scheduler: scheduler, box: box)
    }
}

/// Records evidence and answers active-rung and easier-version lookups from what the test sets up. The easier version
/// is whatever the test says the engine returned; the real engine is covered separately.
@MainActor
private final class TooHardRecorder: AdaptiveEvidenceRecording {
    private(set) var evidence: [AdaptiveEvidence] = []
    private var rungs: [String: ActiveRung] = [:]
    /// What the engine answers; nil means it has no easier version.
    var option: EasierSwapOption?
    var failsToIssue = false
    private(set) var askedFor: [UUID] = []
    private(set) var issued: [IssuedEasierSwap] = []
    private(set) var issuedReplacing: [UUID] = []
    private(set) var issuedTargets: [RungDose] = []

    func setRung(_ rung: ActiveRung, for exerciseID: ExerciseID, reducedRange: Bool = false) {
        rungs["\(exerciseID.rawValue)|\(reducedRange)"] = rung
    }

    func activeRung(for exerciseID: ExerciseID, reducedRange: Bool) -> ActiveRung? {
        rungs["\(exerciseID.rawValue)|\(reducedRange)"]
    }

    func record(_ evidence: AdaptiveEvidence) {
        self.evidence.append(evidence)
    }

    func easierSwapOption(for item: PrescriptionItem, asOf now: Date) -> EasierSwapOption? {
        askedFor.append(item.id)
        return option
    }

    func issueEasierSwap(replacing item: PrescriptionItem, option: EasierSwapOption, at now: Date) -> IssuedEasierSwap? {
        guard !failsToIssue else { return nil }
        let number = issued.count
        let swap = IssuedEasierSwap(
            prescriptionID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, UInt8(0xA0 + number))),
            item: AdaptivePlanItem(
                itemID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, UInt8(0xB0 + number))),
                role: .easierSwap, family: item.family, rungDose: option.target, exerciseID: option.exerciseID,
                reducedRange: option.reducedRange))
        issued.append(swap)
        issuedReplacing.append(item.id)
        issuedTargets.append(option.target)
        return swap
    }
}

private final class TooHardScriptedRecognizer: SpeechRecognizing {
    var onTranscript: ((String, Bool) -> Void)?
    var onStateChanged: ((SpeechRecognizerState) -> Void)?

    func setContextualStrings(_ strings: [String]) {}
    func start() {}
    func stop() {}
    func restartTask() {}
    func reconfigureInput() {}
    func rebuild() {}

    func hear(_ text: String, final: Bool = true) {
        onTranscript?(text, final)
    }
}

@MainActor
private struct TooHardGrantedPermissions: VoicePermissionProviding {
    var microphone: VoicePermissionStatus { .granted }
    var speechRecognition: VoicePermissionStatus { .granted }
    func requestMicrophone(_ completion: @escaping @MainActor (Bool) -> Void) { completion(true) }
    func requestSpeechRecognition(_ completion: @escaping @MainActor (Bool) -> Void) { completion(true) }
}
