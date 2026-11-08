import AdaptiveTraining
import XCTest
@testable import PostureAnalysisApp

/// The optional bonus after an Easy rating: when it is offered, how it runs, what is recorded, and that the app only
/// records it.
@MainActor
final class BonusRepsTests: XCTestCase {
    private let prescriptionID = BonusRepsTests.uuid(0x51)
    private let mainID = BonusRepsTests.uuid(0x52)
    private let sampleID = BonusRepsTests.uuid(0x53)
    private let shallow = VariantID(rawValue: "push.wall_push_up.shallow")
    private let wall = VariantID(rawValue: "push.wall_push_up")

    // MARK: - When the offer opens

    func testEasyOnAnOfferingMainItemOpensTheOfferAndRecordsNothingYet() throws {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        XCTAssertNil(harness.model.bonusOffer, "Nothing is offered before the item is rated.")

        harness.model.rateEffort(.easy)

        let offer = try XCTUnwrap(harness.model.bonusOffer)
        XCTAssertEqual(offer.offered, .reps(1))
        XCTAssertEqual(offer.amountLabel, "1 rep")
        XCTAssertNil(harness.model.effortCard)
        XCTAssertTrue(recorder.evidence.isEmpty, "The item's evidence waits until the bonus is settled.")
        XCTAssertTrue(harness.voice.acceptsBonusAnswer)
        XCTAssertFalse(harness.voice.acceptsEffortFeedback, "The card is closed, so effort phrases go back to commands.")
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete)
        XCTAssertTrue(harness.model.hud.visual.showsCompletionCard, "The reducer is done.")
        XCTAssertFalse(harness.model.showsCompletionCard, "But the completion screen waits for the offer.")
    }

    func testATimedHoldOffersFiveMoreSeconds() throws {
        let exercise = hold(seconds: 20)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .seconds(20)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.scheduler.advance(by: 21)

        harness.model.rateEffort(.easy)

        let offer = try XCTUnwrap(harness.model.bonusOffer)
        XCTAssertEqual(offer.offered, .seconds(5))
        XCTAssertEqual(offer.amountLabel, "5 s")
    }

    func testOkayAndTooHardNeverOfferABonus() throws {
        // Revert check (b): offering after Okay makes this fail.
        for effort in [EffortFeedback.okay, .tooHard] {
            let exercise = selfReported(target: 5)
            let recorder = BonusEvidenceRecorder()
            let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                      recorder: recorder)
            open(harness)
            finishMainItem(harness)

            harness.model.rateEffort(effort)

            XCTAssertNil(harness.model.bonusOffer, "\(effort) is not a reason to offer more.")
            XCTAssertFalse(harness.voice.acceptsBonusAnswer)
            XCTAssertEqual(recorder.evidence.count, 1, "It is recorded at once, as before.")
            XCTAssertEqual(recorder.evidence.first?.effort, effort)
            XCTAssertNil(recorder.evidence.first?.bonus)
        }
    }

    func testAnUnratedItemOffersNothing() {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)

        harness.model.skipEffort()

        XCTAssertNil(harness.model.bonusOffer)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertNil(recorder.evidence.first?.bonus)
    }

    func testAnItemThatDoesNotOfferABonusNeverEarnsOne() {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise],
                                  launch: launch(exercise: exercise, dose: .reps(5), offersBonus: false),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)

        harness.model.rateEffort(.easy)

        XCTAssertNil(harness.model.bonusOffer, "The prescription decides whether an item offers a bonus.")
        XCTAssertEqual(recorder.evidence.count, 1)
    }

    func testManualWorkNeverOffersABonus() {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        recorder.setRung(ActiveRung(family: .push, rungDose: RungDose(variant: wall, dose: .reps(5))), for: exercise.id)
        let routine = WorkoutPlan(id: UUID(), name: "My routine", items: [
            WorkoutPlanItem(id: BonusRepsTests.uuid(0x61), exerciseID: exercise.id, sets: 1, targetReps: 5...5)
        ])
        let harness = makeHarness(exercises: [exercise], launch: nil, plan: routine, recorder: recorder)
        open(harness)
        finishMainItem(harness)
        XCTAssertNotNil(harness.model.effortCard, "A routine exercise that is the active rung still asks.")

        harness.model.rateEffort(.easy)

        XCTAssertNil(harness.model.bonusOffer)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(recorder.evidence.first?.source, .manual)
        XCTAssertNil(recorder.evidence.first?.bonus)
    }

    func testTheHarderSampleNeverOffersABonus() throws {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise],
                                  launch: launch(exercise: exercise, dose: .reps(5), withSample: true),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        harness.model.rateEffort(.okay)
        harness.model.send(.start)
        harness.model.send(.nextSet)
        XCTAssertEqual(harness.model.effortCard?.amount, 1, "The sample's own card is open.")

        harness.model.rateEffort(.easy)

        XCTAssertNil(harness.model.bonusOffer, "The prescription item offers one, but a sample isn't a main item.")
        XCTAssertEqual(recorder.evidence.count, 2)
        let sample = try XCTUnwrap(recorder.evidence.last)
        XCTAssertEqual(sample.prescriptionItemID, sampleID)
        XCTAssertNil(sample.bonus)
        XCTAssertEqual(harness.model.session.plan?.items.filter(\.isBonus).count, 0)
    }

    func testAnItemStoppedEarlyNeverOffersABonus() throws {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        harness.model.adjustEffortAmount(by: -1)

        harness.model.rateEffort(.easy)

        XCTAssertNil(harness.model.bonusOffer, "Four of five reps is less than the prescription.")
        XCTAssertEqual(recorder.evidence.first?.completion, .stoppedEarly)
        XCTAssertNil(recorder.evidence.first?.bonus)
    }

    func testACorrectedAmountThatStillMeetsThePrescriptionStillOffers() {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        harness.model.adjustEffortAmount(by: 1)

        harness.model.rateEffort(.easy)

        XCTAssertNotNil(harness.model.bonusOffer, "Six reps meets a prescription of five.")
        XCTAssertTrue(recorder.evidence.isEmpty)
    }

    func testASkippedItemNeverOffersABonus() {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextExercise)
        XCTAssertEqual(harness.model.effortCard?.amount, 0, "A skipped item opens at zero.")

        harness.model.rateEffort(.easy)

        XCTAssertNil(harness.model.bonusOffer)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(recorder.evidence.first?.completion, .notAttempted)
        XCTAssertNil(recorder.evidence.first?.bonus)
    }

    // MARK: - Declining

    func testDecliningByTapRecordsOneRowWithTheDeclinedBonusAndRunsNothing() throws {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        let cardID = try XCTUnwrap(harness.model.effortCard?.id)
        harness.model.rateEffort(.easy)

        harness.model.declineBonus()

        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(evidence.id, cardID)
        XCTAssertEqual(evidence.bonus, BonusRecord(offered: .reps(1), accepted: false))
        XCTAssertEqual(evidence.effort, .easy, "The rating is the item's own.")
        XCTAssertEqual(evidence.completion, .completed, "Declining is a full success.")
        XCTAssertEqual(evidence.prescriptionItemID, mainID)
        XCTAssertNil(harness.model.bonusOffer)
        XCTAssertFalse(harness.voice.acceptsBonusAnswer)
        XCTAssertEqual(harness.model.session.plan?.items.filter(\.isBonus).count, 0, "No bonus set was made.")
        XCTAssertTrue(harness.model.showsCompletionCard, "Declining moves on at once.")
        let record = try savedRecord(harness)
        XCTAssertFalse(record.entries.contains { $0.name.hasPrefix(WorkoutPlanItem.bonusPrefix) }, "No bonus set is saved.")
    }

    func testDecliningByVoiceRecordsTheSameRow() throws {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        harness.model.rateEffort(.easy)

        harness.voice.emitHeard("I'm done")
        harness.voice.emitBonus(.decline)

        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(recorder.evidence.first?.bonus, BonusRecord(offered: .reps(1), accepted: false))
        XCTAssertNil(harness.model.bonusOffer)
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete, "A bonus answer never runs as a command.")
    }

    func testAnAnswerAfterTheOfferIsSettledDoesNothing() {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        harness.model.rateEffort(.easy)
        harness.model.declineBonus()

        harness.model.declineBonus()
        harness.model.acceptBonus()
        harness.voice.emitBonus(.accept)

        XCTAssertEqual(recorder.evidence.count, 1, "It is recorded once.")
        XCTAssertEqual(harness.model.session.plan?.items.filter(\.isBonus).count, 0)
    }

    // MARK: - Accepting

    func testAcceptingRunsABonusSetAndRecordsOneRowAfterItIsRated() throws {
        // Revert check (a): recording the item's evidence before the bonus is settled makes two rows.
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        let cardID = try XCTUnwrap(harness.model.effortCard?.id)
        harness.model.rateEffort(.easy)

        harness.model.acceptBonus()

        XCTAssertNil(harness.model.bonusOffer)
        XCTAssertFalse(harness.voice.acceptsBonusAnswer)
        XCTAssertTrue(recorder.evidence.isEmpty, "Still waiting: the bonus hasn't been done.")
        let items = try XCTUnwrap(harness.model.session.plan?.items)
        XCTAssertEqual(items.map(\.isBonus), [false, true])
        let bonus = try XCTUnwrap(items.dropFirst().first)
        XCTAssertEqual(items.first?.id, mainID)
        XCTAssertEqual(bonus.exerciseID, exercise.id)
        XCTAssertEqual(bonus.sets, 1)
        XCTAssertEqual(bonus.targetReps, 1...1)
        XCTAssertEqual(harness.model.session.currentPlanItem?.id, bonus.id)
        XCTAssertEqual(harness.model.session.phase, .ready, "Set up like a plan item, with no rest.")
        XCTAssertEqual(harness.model.session.exercise?.targetReps, 1...1)

        harness.model.send(.start)
        XCTAssertEqual(harness.model.session.phase, .exercising)
        XCTAssertNil(harness.model.effortCard, "Starting the bonus doesn't ask anything.")
        harness.model.send(.nextSet)

        let card = try XCTUnwrap(harness.model.effortCard, "The bonus has its own light card.")
        XCTAssertTrue(card.isBonus)
        XCTAssertEqual(card.title, "How was the bonus?")
        XCTAssertEqual(card.amount, 1)
        XCTAssertEqual(card.unit, .reps)
        XCTAssertTrue(recorder.evidence.isEmpty)
        XCTAssertTrue(harness.voice.acceptsEffortFeedback, "Its rating can be spoken too.")
        XCTAssertFalse(harness.model.showsCompletionCard, "The completion screen waits for the bonus card.")

        harness.model.rateEffort(.okay)

        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(recorder.evidence.count, 1, "One row for the item, with its bonus.")
        XCTAssertEqual(evidence.id, cardID)
        XCTAssertEqual(evidence.prescriptionItemID, mainID)
        XCTAssertEqual(evidence.effort, .easy)
        XCTAssertEqual(evidence.confirmed, .reps(5), "The prescribed work is kept apart from the bonus.")
        XCTAssertEqual(evidence.completion, .completed)
        XCTAssertEqual(evidence.bonus, BonusRecord(offered: .reps(1), accepted: true, completed: .reps(1), effort: .okay))
        XCTAssertNil(harness.model.effortCard)
        XCTAssertNil(harness.model.bonusOffer, "A bonus is never offered from a bonus.")
        XCTAssertTrue(harness.model.showsCompletionCard)
        XCTAssertFalse(harness.voice.acceptsEffortFeedback)
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete)
    }

    func testAcceptingByVoiceStartsTheBonus() throws {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        harness.model.rateEffort(.easy)

        harness.voice.emitHeard("one more")
        harness.voice.emitBonus(.accept)

        XCTAssertNil(harness.model.bonusOffer)
        XCTAssertEqual(harness.model.session.plan?.items.map(\.isBonus), [false, true])
        XCTAssertEqual(harness.model.session.phase, .ready)
        XCTAssertTrue(recorder.evidence.isEmpty)
    }

    func testTheSavedWorkoutNamesTheBonusAndShowsItAsABonus() throws {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        harness.model.rateEffort(.easy)
        harness.model.acceptBonus()
        harness.model.send(.start)
        harness.model.send(.nextSet)
        harness.model.rateEffort(.easy)

        let record = try savedRecord(harness)

        XCTAssertEqual(record.entries.map(\.name), [exercise.displayName, "Bonus: \(exercise.displayName)"])
        XCTAssertEqual(record.entries.map(\.outcome), [.completed, .completed])
        XCTAssertEqual(record.entries.last?.sets.map(\.reps), [1])
        XCTAssertEqual(record.planID, AdaptiveTrainingCoordinator.todaySessionPlanID)
        let stats = WorkoutCompletionStats(record: record)
        XCTAssertEqual(stats.exerciseRows.map(\.isBonus), [false, true])
        XCTAssertEqual(stats.exerciseRows.map(\.isOptional), [false, false], "A bonus is not the optional sample.")
        XCTAssertEqual(stats.exerciseCount, 1, "A bonus repeats an exercise already counted.")
        XCTAssertEqual(stats.totalSets, 2)
        XCTAssertEqual(stats.totalReps, 6)
        XCTAssertEqual(stats.exerciseRows.last?.summary, "Bonus: \(exercise.displayName) — 1 set · 1 rep")
    }

    func testATimedBonusRunsFiveSecondsAndRecordsSeconds() throws {
        let exercise = hold(seconds: 20)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .seconds(20)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.scheduler.advance(by: 21)
        harness.model.rateEffort(.easy)
        harness.model.acceptBonus()
        XCTAssertEqual(harness.model.session.exercise?.targetReps, 5...5)

        harness.model.send(.start)
        harness.scheduler.advance(by: 6)

        let card = try XCTUnwrap(harness.model.effortCard)
        XCTAssertTrue(card.isBonus)
        XCTAssertEqual(card.unit, .seconds)
        XCTAssertEqual(card.amountLabel, "5 s")
        harness.model.rateEffort(.easy)

        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(evidence.bonus, BonusRecord(offered: .seconds(5), accepted: true, completed: .seconds(5), effort: .easy))
        XCTAssertEqual(evidence.confirmed, .seconds(20))
    }

    func testAPartialRepBonusRecordsTheSmallerAmountTheUserConfirms() throws {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        harness.model.rateEffort(.easy)
        harness.model.acceptBonus()
        harness.model.send(.start)
        harness.model.send(.nextSet)

        harness.model.adjustEffortAmount(by: -1)
        XCTAssertEqual(harness.model.effortCard?.amount, 0)
        harness.model.skipEffort()

        let bonus = try XCTUnwrap(recorder.evidence.first?.bonus)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(bonus, BonusRecord(offered: .reps(1), accepted: true, completed: .reps(0), effort: nil),
                       "The user took it and did none: zero, which is not the same as not reported.")
    }

    func testAPartialTimedBonusRecordsTheSecondsHeld() throws {
        let exercise = hold(seconds: 20)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .seconds(20)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.scheduler.advance(by: 21)
        harness.model.rateEffort(.easy)
        harness.model.acceptBonus()
        harness.model.send(.start)
        harness.scheduler.advance(by: 3)

        harness.model.send(.nextSet)

        XCTAssertEqual(harness.model.effortCard?.amount, 3, "Done early: the seconds held.")
        harness.model.rateEffort(.okay)
        let bonus = try XCTUnwrap(recorder.evidence.first?.bonus)
        XCTAssertEqual(bonus, BonusRecord(offered: .seconds(5), accepted: true, completed: .seconds(3), effort: .okay))
    }

    func testSkippingTheBonusRatingStillRecordsTheSelfReportedAmount() throws {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        harness.model.rateEffort(.easy)
        harness.model.acceptBonus()
        harness.model.send(.start)
        harness.model.send(.nextSet)

        harness.model.skipEffort()

        XCTAssertEqual(recorder.evidence.first?.bonus,
                       BonusRecord(offered: .reps(1), accepted: true, completed: .reps(1), effort: nil),
                       "The rating is optional.")
    }

    // MARK: - Camera

    func testALostTrackerDuringTheBonusThenAConfirmedAmountIsRecordedAsConfirmed() throws {
        // Revert check (c): clearing the amount whenever tracking was lost makes this fail.
        let wallPushUp = WallPushUpExercise.definition()
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [wallPushUp], launch: launch(exercise: wallPushUp, dose: .reps(1)),
                                  recorder: recorder)
        open(harness)
        var time = 0.0
        driveSet(harness, exercise: wallPushUp, time: &time)
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete)
        harness.model.rateEffort(.easy)
        XCTAssertNotNil(harness.model.bonusOffer)
        harness.model.acceptBonus()
        harness.model.send(.start)
        loseTracking(harness, time: &time)
        XCTAssertFalse(harness.model.session.framing.isReliable)

        harness.model.send(.nextSet)

        let card = try XCTUnwrap(harness.model.effortCard)
        XCTAssertTrue(card.isBonus)
        XCTAssertEqual(card.amount, 0, "The tracker saw nothing.")
        harness.model.adjustEffortAmount(by: 1)
        harness.model.rateEffort(.easy)

        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(evidence.bonus, BonusRecord(offered: .reps(1), accepted: true, completed: .reps(1), effort: .easy),
                       "The user said they did it; a lost tracker doesn't erase that.")
    }

    func testALostTrackerWithNobodyVouchingForTheAmountIsNeverAFailedBonus() throws {
        let wallPushUp = WallPushUpExercise.definition()
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [wallPushUp], launch: launch(exercise: wallPushUp, dose: .reps(1)),
                                  recorder: recorder)
        open(harness)
        var time = 0.0
        driveSet(harness, exercise: wallPushUp, time: &time)
        harness.model.rateEffort(.easy)
        harness.model.acceptBonus()
        harness.model.send(.start)
        loseTracking(harness, time: &time)
        harness.model.send(.nextSet)

        harness.model.rateEffort(.okay)

        let bonus = try XCTUnwrap(recorder.evidence.first?.bonus)
        XCTAssertEqual(bonus.accepted, true)
        XCTAssertNil(bonus.completed, "Not reported: never zero reps because the camera lost the user.")
        XCTAssertEqual(bonus.effort, .okay)
    }

    func testABonusRunsTheSameVariantAndTheCameraCountsItsRep() throws {
        let wallPushUp = WallPushUpExercise.definition()
        let shallowExercise = try XCTUnwrap(wallPushUp.reducedRange?())
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [wallPushUp],
                                  launch: launch(exercise: wallPushUp, dose: .reps(1), reducedRange: true),
                                  recorder: recorder)
        open(harness)
        var time = 0.0
        driveSet(harness, exercise: shallowExercise, time: &time)
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete)
        harness.model.rateEffort(.easy)

        harness.model.acceptBonus()

        let bonus = try XCTUnwrap(harness.model.session.plan?.items.dropFirst().first)
        XCTAssertTrue(bonus.isBonus)
        XCTAssertTrue(bonus.reducedRange, "The bonus is the same variant as the item it follows.")
        XCTAssertEqual(harness.model.session.exercise?.displayName, shallowExercise.displayName)
        driveSet(harness, exercise: shallowExercise, time: &time)
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete, "The camera counted the bonus rep.")
        let card = try XCTUnwrap(harness.model.effortCard)
        XCTAssertTrue(card.isBonus)
        XCTAssertEqual(card.amount, 1)
        harness.model.rateEffort(.okay)

        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(evidence.bonus,
                       BonusRecord(offered: .reps(1), accepted: true, completed: .reps(1), effort: .okay),
                       "A rated, unchanged camera count stands for the user's word.")
        XCTAssertEqual(evidence.variant, shallow)
        let record = try savedRecord(harness)
        XCTAssertEqual(record.entries.map(\.name), [shallowExercise.displayName, "Bonus: \(shallowExercise.displayName)"])
    }

    // MARK: - The offer never blocks

    func testStartingTheNextItemWithTheOfferOpenDeclinesIt() throws {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise],
                                  launch: launch(exercise: exercise, dose: .reps(5), withSample: true),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        harness.model.rateEffort(.easy)
        XCTAssertNotNil(harness.model.bonusOffer)
        XCTAssertEqual(harness.model.session.phase, .resting, "The optional sample is next, after a rest.")

        harness.scheduler.advance(by: 5)
        XCTAssertNotNil(harness.model.bonusOffer, "The offer doesn't pause or end the rest.")

        harness.model.send(.start)

        XCTAssertEqual(harness.model.session.phase, .exercising, "Starting the sample isn't blocked by the offer.")
        XCTAssertNil(harness.model.bonusOffer)
        XCTAssertFalse(harness.voice.acceptsBonusAnswer)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(recorder.evidence.first?.bonus, BonusRecord(offered: .reps(1), accepted: false))
        XCTAssertEqual(recorder.evidence.first?.completion, .completed)
        XCTAssertEqual(harness.model.session.plan?.items.filter(\.isBonus).count, 0)
    }

    func testStartingTheNextSetByVoiceAlsoDeclinesTheOffer() {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise],
                                  launch: launch(exercise: exercise, dose: .reps(5), withSample: true),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        harness.model.rateEffort(.easy)

        harness.voice.emit(.start)

        XCTAssertNil(harness.model.bonusOffer)
        XCTAssertEqual(recorder.evidence.first?.bonus, BonusRecord(offered: .reps(1), accepted: false))
    }

    func testSkippingToTheNextItemWithTheOfferOpenDeclinesIt() throws {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise],
                                  launch: launch(exercise: exercise, dose: .reps(5), withSample: true),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        harness.model.rateEffort(.easy)

        harness.model.send(.nextExercise)

        XCTAssertNil(harness.model.bonusOffer)
        let main = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(main.prescriptionItemID, mainID)
        XCTAssertEqual(main.bonus, BonusRecord(offered: .reps(1), accepted: false))
        XCTAssertNotNil(harness.model.effortCard, "The skipped sample asks about itself.")
    }

    func testEndingTheWorkoutWithTheOfferOpenDeclinesItOnce() throws {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        harness.model.rateEffort(.easy)

        harness.model.send(.endWorkout)
        harness.model.onDisappear()
        harness.model.onDisappear()

        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(recorder.evidence.first?.bonus, BonusRecord(offered: .reps(1), accepted: false))
        XCTAssertNil(harness.model.bonusOffer)
    }

    func testClosingTheScreenWithTheOfferOpenDeclinesItOnce() {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        harness.model.rateEffort(.easy)

        harness.model.onDisappear()
        harness.model.onDisappear()

        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(recorder.evidence.first?.bonus, BonusRecord(offered: .reps(1), accepted: false))
    }

    func testEndingTheWorkoutDuringTheBonusRecordsTheItemOnceWithWhatWasDone() throws {
        let exercise = hold(seconds: 20)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .seconds(20)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.scheduler.advance(by: 21)
        harness.model.rateEffort(.easy)
        harness.model.acceptBonus()
        harness.model.send(.start)
        harness.scheduler.advance(by: 3)

        harness.model.send(.endWorkout)
        harness.model.onDisappear()

        XCTAssertEqual(harness.model.session.phase, .ended)
        XCTAssertNil(harness.model.effortCard, "The workout is over, so nothing is asked.")
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(recorder.evidence.first?.bonus,
                       BonusRecord(offered: .seconds(5), accepted: true, completed: .seconds(3), effort: nil))
        XCTAssertEqual(recorder.evidence.first?.effort, .easy)
    }

    func testEndingTheWorkoutBeforeTheBonusStartsRecordsItAcceptedWithNoAmount() {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        harness.model.rateEffort(.easy)
        harness.model.acceptBonus()

        harness.model.send(.endWorkout)
        harness.model.onDisappear()

        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(recorder.evidence.first?.bonus, BonusRecord(offered: .reps(1), accepted: true))
    }

    func testClosingTheScreenWithTheBonusCardOpenRecordsItOnce() {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        harness.model.rateEffort(.easy)
        harness.model.acceptBonus()
        harness.model.send(.start)
        harness.model.send(.nextSet)
        XCTAssertEqual(harness.model.effortCard?.isBonus, true)

        harness.model.onDisappear()
        harness.model.onDisappear()

        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(recorder.evidence.first?.bonus,
                       BonusRecord(offered: .reps(1), accepted: true, completed: .reps(1), effort: nil),
                       "A self-reported amount is the user's word, rated or not.")
    }

    func testSkippingTheBonusSetBeforeDoingAnythingIsNeitherSkippedNorFailed() throws {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        harness.model.rateEffort(.easy)
        harness.model.acceptBonus()

        harness.model.send(.nextExercise)

        XCTAssertNil(harness.model.effortCard, "Nothing was done, so there is nothing to rate.")
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(recorder.evidence.first?.bonus, BonusRecord(offered: .reps(1), accepted: true))
        let record = try savedRecord(harness)
        XCTAssertEqual(record.entries.map(\.name), [exercise.displayName], "An empty bonus leaves no entry to read as skipped.")
        XCTAssertTrue(harness.model.showsCompletionCard)
    }

    func testTheBonusRunsBeforeTheOptionalSampleAndTheSampleStillFollows() throws {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise],
                                  launch: launch(exercise: exercise, dose: .reps(5), withSample: true),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        harness.model.rateEffort(.easy)
        XCTAssertEqual(harness.model.session.currentPlanItem?.id, sampleID, "The sample is up next, resting.")

        harness.model.acceptBonus()

        let items = try XCTUnwrap(harness.model.session.plan?.items)
        XCTAssertEqual(items.map(\.isBonus), [false, true, false])
        XCTAssertEqual(items.first?.id, mainID)
        XCTAssertEqual(items.last?.id, sampleID)
        XCTAssertEqual(harness.model.session.currentPlanItem?.isBonus, true)
        XCTAssertEqual(harness.model.session.phase, .ready, "The rest was cancelled: the bonus starts like a plan item.")
        XCTAssertNil(harness.model.session.restRemaining(at: harness.clock.now))

        harness.model.send(.start)
        harness.model.send(.nextSet)
        harness.model.rateEffort(.easy)

        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(recorder.evidence.first?.prescriptionItemID, mainID)
        XCTAssertEqual(harness.model.session.currentPlanItem?.id, sampleID, "The sample follows the bonus.")
        XCTAssertEqual(harness.model.session.phase, .resting)
        harness.model.send(.start)
        harness.model.send(.nextSet)
        harness.model.rateEffort(.okay)
        XCTAssertEqual(recorder.evidence.count, 2)
        XCTAssertEqual(recorder.evidence.last?.prescriptionItemID, sampleID)
        XCTAssertNil(recorder.evidence.last?.bonus)
    }

    // MARK: - Voice

    func testAnOpenOfferAsksTheVoiceControllerToListenForItsAnswer() {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        XCTAssertFalse(harness.voice.acceptsBonusAnswer, "Only listened for while the offer is open.")

        harness.model.rateEffort(.easy)
        XCTAssertTrue(harness.voice.acceptsBonusAnswer)

        harness.model.declineBonus()
        XCTAssertFalse(harness.voice.acceptsBonusAnswer)
    }

    func testTheCommandsStillWorkWhileTheOfferIsOpen() {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise],
                                  launch: launch(exercise: exercise, dose: .reps(5), withSample: true),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        harness.model.rateEffort(.easy)

        harness.voice.emit(.whichSet)

        XCTAssertNotNil(harness.model.bonusOffer, "A status question doesn't answer the offer.")
        XCTAssertTrue(recorder.evidence.isEmpty)
    }

    // MARK: - The reducer

    func testTheReducerInsertsTheBonusRightAfterItsItemAndSetsItUpWithoutARest() throws {
        var session = makeSession(withSample: false)
        XCTAssertEqual(session.phase, .exerciseComplete)

        let effects = session.handle(.startBonus(BonusRequest(itemID: bonusID, after: mainID, amount: 1)), at: 4)

        let items = try XCTUnwrap(session.plan?.items)
        XCTAssertEqual(items.map(\.id), [mainID, bonusID])
        let bonus = try XCTUnwrap(items.last)
        XCTAssertTrue(bonus.isBonus)
        XCTAssertTrue(bonus.reducedRange, "Same variant as the item it follows.")
        XCTAssertEqual(bonus.exerciseID, .wallPushUp)
        XCTAssertEqual(bonus.targetReps, 1...1)
        XCTAssertEqual(session.currentPlanItem?.id, bonusID)
        XCTAssertTrue(session.phase == .ready || session.phase == .framing, "Set up, not resting or exercising.")
        XCTAssertNil(session.restEndsAt)
        XCTAssertEqual(session.planPositionLabel, "Bonus")
        XCTAssertTrue(effects.contains { if case .speak = $0 { return true } else { return false } })
        XCTAssertEqual(bonus.label(for: ExerciseCatalog.definition(for: .wallPushUp)), "Bonus: Shallow Wall Push-Up")
    }

    func testTheBonusSetCompletesIntoItsOwnRecordAndThePlanEndsAgain() throws {
        var session = makeSession(withSample: false)
        _ = session.handle(.startBonus(BonusRequest(itemID: bonusID, after: mainID, amount: 1)), at: 4)

        _ = session.handle(.command(.start), at: 5)
        _ = session.handle(.command(.nextSet), at: 6)

        XCTAssertEqual(session.phase, .exerciseComplete)
        XCTAssertEqual(session.planRecords[bonusID]?.outcome, .completed)
        XCTAssertEqual(session.planRecords[bonusID]?.setReps.count, 1, "The bonus counts its own set.")
        XCTAssertEqual(session.planRecords[mainID]?.setReps.count, 1)
    }

    func testTheSampleStillFollowsTheBonusAndPositionsIgnoreIt() throws {
        var session = makeSession(withSample: true)
        XCTAssertEqual(session.currentPlanItem?.id, sampleID)
        XCTAssertEqual(session.planPositionLabel, "Exercise 2 of 2")

        _ = session.handle(.startBonus(BonusRequest(itemID: bonusID, after: mainID, amount: 1)), at: 4)

        XCTAssertEqual(session.plan?.items.map(\.id), [mainID, bonusID, sampleID])
        XCTAssertEqual(session.currentPlanItem?.id, bonusID)
        _ = session.handle(.command(.start), at: 5)
        _ = session.handle(.command(.nextSet), at: 6)
        XCTAssertEqual(session.currentPlanItem?.id, sampleID)
        XCTAssertEqual(session.phase, .resting)
        XCTAssertEqual(session.planPositionLabel, "Exercise 2 of 2", "The bonus isn't one of the exercises.")
    }

    func testTheReducerRefusesABonusItCannotRun() throws {
        // A skipped item, an unknown item, a zero amount, a second bonus, and a set already under way.
        var skipped = makeSession(withSample: false, skipMain: true)
        let skippedEffects = skipped.handle(.startBonus(BonusRequest(itemID: bonusID, after: mainID, amount: 1)), at: 4)
        XCTAssertEqual(skipped.plan?.items.count, 1)
        XCTAssertTrue(skippedEffects.isEmpty)

        var session = makeSession(withSample: false)
        _ = session.handle(.startBonus(BonusRequest(itemID: bonusID, after: BonusRepsTests.uuid(0x7F), amount: 1)), at: 4)
        _ = session.handle(.startBonus(BonusRequest(itemID: bonusID, after: mainID, amount: 0)), at: 4)
        XCTAssertEqual(session.plan?.items.count, 1)

        _ = session.handle(.startBonus(BonusRequest(itemID: bonusID, after: mainID, amount: 1)), at: 4)
        _ = session.handle(.startBonus(BonusRequest(itemID: BonusRepsTests.uuid(0x7E), after: mainID, amount: 1)), at: 4)
        XCTAssertEqual(session.plan?.items.count, 2, "Only one bonus follows an item.")

        var running = makeSession(withSample: true)
        _ = running.handle(.command(.start), at: 4)
        XCTAssertEqual(running.phase, .exercising)
        _ = running.handle(.startBonus(BonusRequest(itemID: bonusID, after: mainID, amount: 1)), at: 5)
        XCTAssertEqual(running.plan?.items.count, 2, "The sample has started, so it is too late.")

        var bonusOfBonus = makeSession(withSample: false)
        _ = bonusOfBonus.handle(.startBonus(BonusRequest(itemID: bonusID, after: mainID, amount: 1)), at: 4)
        _ = bonusOfBonus.handle(.command(.start), at: 5)
        _ = bonusOfBonus.handle(.command(.nextSet), at: 6)
        _ = bonusOfBonus.handle(.startBonus(BonusRequest(itemID: BonusRepsTests.uuid(0x7D), after: bonusID, amount: 1)), at: 7)
        XCTAssertEqual(bonusOfBonus.plan?.items.count, 2, "A bonus is never offered again from a bonus.")
    }

    func testAnotherRoundOfThePlanDropsTheBonus() {
        var session = makeSession(withSample: false)
        _ = session.handle(.startBonus(BonusRequest(itemID: bonusID, after: mainID, amount: 1)), at: 4)
        _ = session.handle(.command(.start), at: 5)
        _ = session.handle(.command(.nextSet), at: 6)
        XCTAssertEqual(session.phase, .exerciseComplete)

        _ = session.handle(.command(.anotherRound), at: 7)

        XCTAssertEqual(session.plan?.items.map(\.id), [mainID], "A new round starts from what was prescribed.")
        XCTAssertEqual(session.currentPlanItem?.id, mainID)
    }

    func testPositionsInAPlanWithoutABonusReadAsBefore() {
        let plan = WorkoutPlan(id: nil, name: "Plan", items: [
            WorkoutPlanItem(id: mainID, exerciseID: .wallPushUp, sets: 1, targetReps: 3...3),
            WorkoutPlanItem(id: sampleID, exerciseID: .wallPushUp, sets: 1, targetReps: 1...1)
        ])
        let session = WorkoutSession(exercises: ExerciseCatalog.all, initialExercise: .wallPushUp, plan: plan)

        XCTAssertEqual(session.planPositionLabel, "Exercise 1 of 2")
    }

    // MARK: - Saved names, stats, and recordings

    func testAnEmptyBonusLeavesNoSavedEntryAndANormalBonusFollowsItsItem() throws {
        var skipped = makeSession(withSample: false)
        _ = skipped.handle(.startBonus(BonusRequest(itemID: bonusID, after: mainID, amount: 1)), at: 4)
        _ = skipped.handle(.command(.nextExercise), at: 5)
        let skippedRecord = try XCTUnwrap(WorkoutRecord(session: skipped, startedAt: Date(timeIntervalSince1970: 0),
                                                        endedAt: Date(timeIntervalSince1970: 30)))
        XCTAssertEqual(skippedRecord.entries.map(\.name), ["Shallow Wall Push-Up"])

        var done = makeSession(withSample: false)
        _ = done.handle(.startBonus(BonusRequest(itemID: bonusID, after: mainID, amount: 1)), at: 4)
        _ = done.handle(.command(.start), at: 5)
        _ = done.handle(.command(.nextSet), at: 6)
        let record = try XCTUnwrap(WorkoutRecord(session: done, startedAt: Date(timeIntervalSince1970: 0),
                                                 endedAt: Date(timeIntervalSince1970: 30)))
        XCTAssertEqual(record.entries.map(\.name), ["Shallow Wall Push-Up", "Bonus: Shallow Wall Push-Up"])
    }

    func testTheCompletionStatsShowABonusAsABonusBesideTheOptionalSample() {
        let record = WorkoutRecord(
            startedAt: Date(timeIntervalSince1970: 100), endedAt: Date(timeIntervalSince1970: 140),
            planID: AdaptiveTrainingCoordinator.todaySessionPlanID, planName: "Today's Session",
            entries: [
                WorkoutRecordEntry(exerciseID: .wallPushUp, name: "Shallow Wall Push-Up", outcome: .completed,
                                   sets: [RecordedSet(reps: 3)]),
                WorkoutRecordEntry(exerciseID: .wallPushUp, name: "Bonus: Shallow Wall Push-Up", outcome: .completed,
                                   sets: [RecordedSet(reps: 1)]),
                WorkoutRecordEntry(exerciseID: .wallPushUp, name: "Optional: Wall Push-Up", outcome: .skipped, sets: [])
            ])

        let stats = WorkoutCompletionStats(record: record)

        XCTAssertEqual(stats.exerciseRows.map(\.isBonus), [false, true, false])
        XCTAssertEqual(stats.exerciseRows.map(\.isOptional), [false, false, true])
        XCTAssertEqual(stats.exerciseRows.map(\.name), ["Shallow Wall Push-Up", "Bonus: Shallow Wall Push-Up", "Optional: Wall Push-Up"])
        XCTAssertEqual(stats.exerciseRows.dropFirst().first?.summary, "Bonus: Shallow Wall Push-Up — 1 set · 1 rep")
        XCTAssertEqual(stats.exerciseRows.last?.summary, "Optional: Wall Push-Up — Optional, skipped")
        XCTAssertEqual(stats.exerciseCount, 2, "The main item and the sample; the bonus repeats the main item.")
        XCTAssertEqual(stats.totalSets, 2)
        XCTAssertEqual(stats.totalReps, 4)
    }

    func testARecordingMarksABonusPlanItemAndWritesTheStartBonusInput() throws {
        let exercise = selfReported(target: 5)
        let store = MemoryWorkoutRecordingStore()
        let recorder = WorkoutSessionRecorder(store: store)
        let evidence = BonusEvidenceRecorder()
        let launch = launch(exercise: exercise, dose: .reps(5))
        let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), exercises: [exercise],
                                               initialExercise: exercise.id, recorder: recorder, plan: launch.plan,
                                               adaptive: evidence, todayLaunch: launch)
        open(harness)
        finishMainItem(harness)
        harness.model.rateEffort(.easy)

        harness.model.acceptBonus()

        let text = store.writer(for: recorder.id).lines.joined(separator: "\n")
        XCTAssertTrue(text.contains(#""type":"bonus""#), "The input that inserted the set is in the recording.")
        XCTAssertTrue(text.contains(#""after":"\#(mainID.uuidString)""#))
        XCTAssertFalse(text.contains(#""bonus":true"#), "The header's plan was written before any bonus existed.")

        let bonusPlan = WorkoutPlan(id: nil, name: "Plan", items: [
            WorkoutPlanItem(id: mainID, exerciseID: exercise.id, sets: 1, targetReps: 5...5),
            WorkoutPlanItem(id: bonusID, exerciseID: exercise.id, sets: 1, targetReps: 1...1, isBonus: true)
        ])
        let secondStore = MemoryWorkoutRecordingStore()
        let secondRecorder = WorkoutSessionRecorder(store: secondStore)
        let second = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), exercises: [exercise],
                                              initialExercise: exercise.id, recorder: secondRecorder, plan: bonusPlan)
        open(second)
        let secondText = secondStore.writer(for: secondRecorder.id).lines.joined(separator: "\n")
        XCTAssertTrue(secondText.contains(#""bonus":true"#), "A bonus plan item says so.")
        XCTAssertEqual(secondText.components(separatedBy: #""bonus":true"#).count - 1, 1, "Only the bonus item says so.")
    }

    // MARK: - Evidence mapping

    func testTheOfferNeedsAMainItemRatedEasyAndDoneInFull() {
        let identity = WorkoutOutcomeAdapter.Identity(
            origin: .adaptive(prescriptionID: prescriptionID, itemID: mainID, prescribed: .reps(5)),
            family: .push, variant: wall, offersBonus: true)
        let completed = finished(amounts: [5], target: 5, result: .completed)
        let easy = WorkoutOutcomeAdapter.Answer(effort: .easy, amount: 5, isAdjusted: false)

        XCTAssertEqual(WorkoutOutcomeAdapter.bonusOffer(identity: identity, item: completed, answer: easy), .reps(1))

        // Each condition on its own.
        XCTAssertNil(WorkoutOutcomeAdapter.bonusOffer(
            identity: identity, item: completed, answer: .init(effort: .okay, amount: 5, isAdjusted: false)))
        XCTAssertNil(WorkoutOutcomeAdapter.bonusOffer(
            identity: identity, item: completed, answer: .init(effort: .tooHard, amount: 5, isAdjusted: false)))
        XCTAssertNil(WorkoutOutcomeAdapter.bonusOffer(
            identity: identity, item: completed, answer: .init(effort: nil, amount: 5, isAdjusted: false)))
        XCTAssertNil(WorkoutOutcomeAdapter.bonusOffer(
            identity: WorkoutOutcomeAdapter.Identity(origin: identity.origin, family: .push, variant: wall,
                                                     offersBonus: false),
            item: completed, answer: easy))
        XCTAssertNil(WorkoutOutcomeAdapter.bonusOffer(
            identity: WorkoutOutcomeAdapter.Identity(origin: .manual, family: .push, variant: wall, offersBonus: true),
            item: completed, answer: easy))
        XCTAssertNil(WorkoutOutcomeAdapter.bonusOffer(
            identity: identity, item: finished(amounts: [3], target: 5, result: .skipped), answer: easy))
        XCTAssertNil(WorkoutOutcomeAdapter.bonusOffer(
            identity: identity, item: finished(amounts: [3], target: 5, result: .endedWorkout), answer: easy))
        XCTAssertNil(WorkoutOutcomeAdapter.bonusOffer(
            identity: identity, item: finished(amounts: [5], target: 5, result: .completed, isBonus: true), answer: easy))
    }

    func testTheOfferBoundaryIsTheCardsAmountAgainstThePrescription() {
        let identity = WorkoutOutcomeAdapter.Identity(
            origin: .adaptive(prescriptionID: prescriptionID, itemID: mainID, prescribed: .reps(5)),
            family: .push, variant: wall, offersBonus: true)
        let item = finished(amounts: [5], target: 5, result: .completed)

        let atTarget = WorkoutOutcomeAdapter.Answer(effort: .easy, amount: 5, isAdjusted: true)
        let belowTarget = WorkoutOutcomeAdapter.Answer(effort: .easy, amount: 4, isAdjusted: true)
        let aboveTarget = WorkoutOutcomeAdapter.Answer(effort: .easy, amount: 6, isAdjusted: true)

        XCTAssertNotNil(WorkoutOutcomeAdapter.bonusOffer(identity: identity, item: item, answer: atTarget))
        XCTAssertNil(WorkoutOutcomeAdapter.bonusOffer(identity: identity, item: item, answer: belowTarget))
        XCTAssertNotNil(WorkoutOutcomeAdapter.bonusOffer(identity: identity, item: item, answer: aboveTarget))
    }

    func testTheBonusDoseIsOneRepOrFiveSeconds() {
        XCTAssertEqual(WorkoutOutcomeAdapter.bonusDose(for: .reps), .reps(1))
        XCTAssertEqual(WorkoutOutcomeAdapter.bonusDose(for: .seconds), .seconds(5))
    }

    func testTheBonusRecordMapsEachBranchWithoutReadingTheTrackerAlone() {
        let selfReportedItem = finished(amounts: [1], target: 1, result: .completed, tracking: .selfReported)
        let cameraItem = finished(amounts: [1], target: 1, result: .completed, tracking: .camera)
        let lostItem = finished(amounts: [0], target: 1, result: .completed, tracking: .camera, trackingLost: true)
        let rated = { (effort: EffortFeedback?, amount: Int, adjusted: Bool) in
            WorkoutOutcomeAdapter.Answer(effort: effort, amount: amount, isAdjusted: adjusted)
        }

        // Declined: nothing else.
        XCTAssertEqual(WorkoutOutcomeAdapter.bonusRecord(offered: .reps(1), accepted: false, item: nil, answer: nil),
                       BonusRecord(offered: .reps(1), accepted: false))
        // Accepted, never finished.
        XCTAssertEqual(WorkoutOutcomeAdapter.bonusRecord(offered: .reps(1), accepted: true, item: nil, answer: nil),
                       BonusRecord(offered: .reps(1), accepted: true))
        // Self-reported: the user's word, rated or not.
        XCTAssertEqual(WorkoutOutcomeAdapter.bonusRecord(offered: .reps(1), accepted: true, item: selfReportedItem,
                                                         answer: rated(nil, 1, false)),
                       BonusRecord(offered: .reps(1), accepted: true, completed: .reps(1)))
        // A camera count the user rated without changing stands for their word.
        XCTAssertEqual(WorkoutOutcomeAdapter.bonusRecord(offered: .reps(1), accepted: true, item: cameraItem,
                                                         answer: rated(.easy, 1, false)),
                       BonusRecord(offered: .reps(1), accepted: true, completed: .reps(1), effort: .easy))
        // An unrated, unchanged camera count is nobody's word.
        XCTAssertEqual(WorkoutOutcomeAdapter.bonusRecord(offered: .reps(1), accepted: true, item: cameraItem,
                                                         answer: rated(nil, 1, false)),
                       BonusRecord(offered: .reps(1), accepted: true))
        // A corrected amount is the user's word whatever the tracker did, including after tracking was lost.
        XCTAssertEqual(WorkoutOutcomeAdapter.bonusRecord(offered: .reps(1), accepted: true, item: lostItem,
                                                         answer: rated(.okay, 1, true)),
                       BonusRecord(offered: .reps(1), accepted: true, completed: .reps(1), effort: .okay))
        XCTAssertEqual(WorkoutOutcomeAdapter.bonusRecord(offered: .reps(1), accepted: true, item: lostItem,
                                                         answer: rated(nil, 0, true)),
                       BonusRecord(offered: .reps(1), accepted: true, completed: .reps(0)),
                       "A confirmed zero is a fact; it is not the same as not reported.")
        // Lost tracking with nothing changed never becomes a count.
        XCTAssertEqual(WorkoutOutcomeAdapter.bonusRecord(offered: .reps(1), accepted: true, item: lostItem,
                                                         answer: rated(.easy, 0, false)),
                       BonusRecord(offered: .reps(1), accepted: true, completed: nil, effort: .easy))
    }

    func testEvidenceCarriesTheBonusAndKeepsThePrescribedWorkApart() {
        let identity = WorkoutOutcomeAdapter.Identity(
            origin: .adaptive(prescriptionID: prescriptionID, itemID: mainID, prescribed: .reps(5)),
            family: .push, variant: wall, offersBonus: true)
        let bonus = BonusRecord(offered: .reps(1), accepted: true, completed: .reps(1), effort: .easy)

        let evidence = WorkoutOutcomeAdapter.evidence(
            id: BonusRepsTests.uuid(0x70), recordedAt: Date(timeIntervalSince1970: 1_000), workoutID: nil,
            identity: identity, item: finished(amounts: [5], target: 5, result: .completed),
            answer: .init(effort: .easy, amount: 5, isAdjusted: false), bonus: bonus)

        XCTAssertEqual(evidence.bonus, bonus)
        XCTAssertEqual(evidence.confirmed, .reps(5), "The bonus isn't added to the prescribed amount.")
        XCTAssertEqual(evidence.prescribed, .reps(5))
        XCTAssertEqual(evidence.setAmounts, [.reps(5)])
        XCTAssertEqual(evidence.completion, .completed)
        XCTAssertNil(WorkoutOutcomeAdapter.evidence(
            id: BonusRepsTests.uuid(0x71), recordedAt: Date(timeIntervalSince1970: 1_000), workoutID: nil,
            identity: identity, item: finished(amounts: [5], target: 5, result: .completed),
            answer: .init(effort: .easy, amount: 5, isAdjusted: false)).bonus, "No bonus unless one is passed.")
    }

    // MARK: - The engine only records it

    func testAnAcceptedBonusIsRecordedButNeverMovesThePrescription() throws {
        let facts = AdaptiveFacts(calibrations: [calibration(.push, at: shallow, dose: .reps(3))])
        let plain = makeEngineRig(facts: facts)
        let withBonus = makeEngineRig(facts: facts)
        let identity = WorkoutOutcomeAdapter.Identity(
            origin: .adaptive(prescriptionID: prescriptionID, itemID: mainID, prescribed: .reps(3)),
            family: .push, variant: shallow, offersBonus: true)
        let item = finished(amounts: [3], target: 3, result: .completed, tracking: .camera)
        let easy = WorkoutOutcomeAdapter.Answer(effort: .easy, amount: 3, isAdjusted: false)
        let bonus = BonusRecord(offered: .reps(1), accepted: true, completed: .reps(1), effort: .easy)
        let evidenceID = BonusRepsTests.uuid(0x72)

        plain.coordinator.record(WorkoutOutcomeAdapter.evidence(
            id: evidenceID, recordedAt: date(day: 20, hour: 11), workoutID: nil, identity: identity, item: item, answer: easy))
        withBonus.coordinator.record(WorkoutOutcomeAdapter.evidence(
            id: evidenceID, recordedAt: date(day: 20, hour: 11), workoutID: nil, identity: identity, item: item, answer: easy,
            bonus: bonus))

        let stored = try XCTUnwrap(withBonus.store.loadFacts().evidence.first)
        XCTAssertEqual(stored.bonus, bonus, "The engine kept the bonus with the item's evidence.")
        XCTAssertEqual(stored.effort, .easy)
        XCTAssertNil(try plain.store.loadFacts().evidence.first?.bonus)

        let plainProfile = try plain.engine.profile()
        let bonusProfile = try withBonus.engine.profile()
        let plainState = try XCTUnwrap(plainProfile.state(.push))
        let bonusState = try XCTUnwrap(bonusProfile.state(.push))
        XCTAssertEqual(bonusState.current, plainState.current, "A bonus never moves the prescription.")
        XCTAssertEqual(bonusState.easyStreak, plainState.easyStreak)
        XCTAssertEqual(bonusState.harderSampleDue, plainState.harderSampleDue)
        XCTAssertEqual(bonusState.comfortableDoses, plainState.comfortableDoses)
        XCTAssertEqual(bonusState.confidence, plainState.confidence)
        XCTAssertEqual(bonusProfile.transitions.map(\.kind), plainProfile.transitions.map(\.kind))
        XCTAssertEqual(bonusProfile.transitions.map(\.to), plainProfile.transitions.map(\.to))
        XCTAssertTrue(bonusProfile.transitions.contains { $0.rationale.codes.contains(.bonusRecordedOnly) },
                      "The replay notes that the bonus was only recorded.")
        XCTAssertFalse(plainProfile.transitions.contains { $0.rationale.codes.contains(.bonusRecordedOnly) })

        let tomorrow = date(day: 21)
        guard case .ready(let plainSession) = plain.coordinator.status(asOf: tomorrow),
              case .ready(let bonusSession) = withBonus.coordinator.status(asOf: tomorrow) else {
            return XCTFail("Both should be ready tomorrow.")
        }
        XCTAssertEqual(bonusSession.main, plainSession.main)
        XCTAssertEqual(bonusSession.harderSample, plainSession.harderSample)
    }

    func testADeclinedBonusIsNeutralToo() throws {
        let facts = AdaptiveFacts(calibrations: [calibration(.push, at: shallow, dose: .reps(3))])
        let plain = makeEngineRig(facts: facts)
        let declined = makeEngineRig(facts: facts)
        let identity = WorkoutOutcomeAdapter.Identity(
            origin: .adaptive(prescriptionID: prescriptionID, itemID: mainID, prescribed: .reps(3)),
            family: .push, variant: shallow, offersBonus: true)
        let item = finished(amounts: [3], target: 3, result: .completed, tracking: .camera)
        let easy = WorkoutOutcomeAdapter.Answer(effort: .easy, amount: 3, isAdjusted: false)
        let evidenceID = BonusRepsTests.uuid(0x73)

        plain.coordinator.record(WorkoutOutcomeAdapter.evidence(
            id: evidenceID, recordedAt: date(day: 20, hour: 11), workoutID: nil, identity: identity, item: item, answer: easy))
        declined.coordinator.record(WorkoutOutcomeAdapter.evidence(
            id: evidenceID, recordedAt: date(day: 20, hour: 11), workoutID: nil, identity: identity, item: item, answer: easy,
            bonus: BonusRecord(offered: .reps(1), accepted: false)))

        XCTAssertEqual(try declined.engine.profile().state(.push)?.current, try plain.engine.profile().state(.push)?.current)
        XCTAssertEqual(try declined.engine.profile().state(.push)?.easyStreak, try plain.engine.profile().state(.push)?.easyStreak)
    }

    // MARK: - Voice phrases

    func testBonusPhrasesAcceptAndDecline() {
        for phrase in ["one more", "one more rep", "sure", "yes", "yes please", "okay one more", "um sure", "One more!"] {
            XCTAssertEqual(BonusPhraseParser.parse(phrase)?.answer, .accept, phrase)
        }
        for phrase in ["I'm done", "I\u{2019}m done", "i am done", "no thanks", "no thank you", "no", "done", "okay no", "um done"] {
            XCTAssertEqual(BonusPhraseParser.parse(phrase)?.answer, .decline, phrase)
        }
        XCTAssertEqual(BonusPhraseParser.parse("one more rep")?.phrase, "one more rep", "The longest phrase wins.")
    }

    func testBonusPhrasesRejectCommandsAndMixedAnswers() {
        for phrase in ["okay start", "okay", "start", "yes end workout", "sure pause", "no start", "yes no", "one more set please start",
                       "easy", "too hard", "not done", "next set", "skip", ""] {
            XCTAssertNil(BonusPhraseParser.parse(phrase), "\"\(phrase)\" is not a bonus answer.")
        }
    }

    func testEffortPhrasesAreNotBonusAnswersAndTheOtherWayRound() {
        XCTAssertNil(BonusPhraseParser.parse("okay"))
        XCTAssertNil(EffortPhraseParser.parse("one more"))
        XCTAssertNil(EffortPhraseParser.parse("yes"))
    }

    func testABonusAnswerAnswersTheOfferAndNeverRunsAsACommand() {
        let rig = makeVoiceRig()
        rig.controller.acceptsBonusAnswer = true

        rig.recognizer.hear("one more")
        rig.recognizer.hear("I'm done")

        XCTAssertEqual(rig.answers, [.accept, .decline])
        XCTAssertTrue(rig.commands.isEmpty, "A command parser that matches everything must not see a bonus answer.")
        XCTAssertEqual(rig.heard, ["one more", "I'm done"])
        XCTAssertEqual(rig.recognizer.restartCount, 2, "Each answer ends the utterance.")
    }

    func testEveryListedBonusAnswerReachesTheOffer() {
        let rig = makeVoiceRig()
        rig.controller.acceptsBonusAnswer = true

        for phrase in ["one more", "one more rep", "sure", "yes", "I'm done", "no thanks", "no", "done"] {
            rig.recognizer.hear(phrase)
        }

        XCTAssertEqual(rig.answers, [.accept, .accept, .accept, .accept, .decline, .decline, .decline, .decline])
        XCTAssertTrue(rig.commands.isEmpty)
    }

    func testWithoutAnOpenOfferBonusPhrasesStayWithTheCommandParser() {
        let rig = makeVoiceRig()
        rig.controller.acceptsBonusAnswer = false

        rig.recognizer.hear("yes")

        XCTAssertTrue(rig.answers.isEmpty)
        XCTAssertEqual(rig.commands, [.pause])
    }

    func testOkayStartIsNotABonusAnswerAndStartsTheSet() {
        let rig = makeVoiceRig(parser: VoiceCommandParser(exercises: ExerciseCatalog.all))
        rig.controller.acceptsBonusAnswer = true

        rig.recognizer.hear("okay start", final: true)

        XCTAssertTrue(rig.answers.isEmpty)
        XCTAssertEqual(rig.commands, [.start], "The offer doesn't swallow commands.")
    }

    func testTheOtherCommandsStillWorkWithTheOfferOpen() {
        let rig = makeVoiceRig(parser: VoiceCommandParser(exercises: ExerciseCatalog.all))
        rig.controller.acceptsBonusAnswer = true

        rig.recognizer.hear("start")
        rig.recognizer.hear("pause")
        rig.recognizer.hear("yes end workout")

        XCTAssertTrue(rig.answers.isEmpty)
        XCTAssertEqual(rig.commands, [.start, .pause, .endWorkout])
    }

    func testAStreamingYesThatBecomesACommandNeverAnswersTheOffer() {
        let rig = makeVoiceRig(parser: VoiceCommandParser(exercises: ExerciseCatalog.all))
        rig.controller.acceptsBonusAnswer = true

        rig.recognizer.hear("yes", final: false)
        XCTAssertTrue(rig.answers.isEmpty, "A partial \"yes\" could still become a command, so it waits.")
        rig.advance(0.3)
        rig.recognizer.hear("yes end workout", final: false)
        rig.advance(0.8)

        XCTAssertTrue(rig.answers.isEmpty)
        XCTAssertEqual(rig.commands, [.endWorkout])
    }

    func testAStandaloneStreamingOneMoreAnswersOnceItSettles() {
        let rig = makeVoiceRig(parser: VoiceCommandParser(exercises: ExerciseCatalog.all))
        rig.controller.acceptsBonusAnswer = true

        rig.recognizer.hear("one more", final: false)
        rig.advance(0.3)
        XCTAssertTrue(rig.answers.isEmpty, "Not settled yet.")
        rig.advance(0.5)

        XCTAssertEqual(rig.answers, [.accept])
        rig.advance(2)
        XCTAssertEqual(rig.answers, [.accept], "It answers once.")
    }

    func testAnAnswerPendingWhenTheOfferClosesIsDropped() {
        let rig = makeVoiceRig(parser: VoiceCommandParser(exercises: ExerciseCatalog.all))
        rig.controller.acceptsBonusAnswer = true
        rig.recognizer.hear("yes", final: false)

        rig.controller.acceptsBonusAnswer = false
        rig.advance(2)

        XCTAssertTrue(rig.answers.isEmpty)
        XCTAssertTrue(rig.commands.isEmpty)
    }

    func testTheEffortCardKeepsItsOwnPhrasesWhileTheOfferIsClosed() {
        let rig = makeVoiceRig()
        rig.controller.acceptsEffortFeedback = true

        rig.recognizer.hear("yes")

        XCTAssertTrue(rig.answers.isEmpty, "Bonus answers are only heard while the offer is open.")
        XCTAssertEqual(rig.commands, [.pause])
    }

    // MARK: - Views' state

    func testTheBonusCardStateTitlesItself() {
        let prescribed = EffortCardState(id: UUID(), unit: .reps, setCount: 1, amount: 3)
        let bonus = EffortCardState(id: UUID(), unit: .seconds, setCount: 1, amount: 5, isBonus: true)

        XCTAssertEqual(prescribed.title, "How was that?")
        XCTAssertFalse(prescribed.isBonus)
        XCTAssertEqual(bonus.title, "How was the bonus?")
        XCTAssertEqual(bonus.amountLabel, "5 s")
        XCTAssertEqual(BonusOfferState(id: UUID(), offered: .reps(1)).amountLabel, "1 rep")
        XCTAssertEqual(BonusOfferState(id: UUID(), offered: .seconds(5)).amountLabel, "5 s")
    }

    // MARK: - Review round: closing during the bonus

    func testClosingTheScreenDuringARunningTimedBonusRecordsOneRowWithTheSecondsHeld() throws {
        // Revert check (review 1): a flush that doesn't read the set under way saves `completed: nil` here.
        let harness = timedBonusRunning(recorder: BonusEvidenceRecorder()) { $0.scheduler.advance(by: 3) }
        let recorder = harness.recorder

        harness.coach.model.onDisappear()
        harness.coach.model.onDisappear()
        harness.coach.model.send(.closeWorkout)

        XCTAssertEqual(recorder.evidence.count, 1, "Repeated close callbacks record once.")
        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(evidence.prescriptionItemID, mainID)
        XCTAssertEqual(evidence.effort, .easy)
        XCTAssertEqual(evidence.bonus, BonusRecord(offered: .seconds(5), accepted: true, completed: .seconds(3)),
                       "The three seconds held are the user's own timed amount; there was no card to rate it.")
    }

    func testClosingTheScreenDuringAPausedTimedBonusKeepsTheSecondsHeldBeforeThePause() throws {
        let harness = timedBonusRunning(recorder: BonusEvidenceRecorder()) {
            $0.scheduler.advance(by: 3)
            $0.model.send(.pause)
            $0.scheduler.advance(by: 30)
        }

        harness.coach.model.onDisappear()
        harness.coach.model.onDisappear()

        XCTAssertEqual(harness.recorder.evidence.count, 1)
        XCTAssertEqual(harness.recorder.evidence.first?.bonus,
                       BonusRecord(offered: .seconds(5), accepted: true, completed: .seconds(3)))
    }

    func testClosingTheScreenBeforeAnySecondsHaveRunInventsNoAmount() {
        let harness = timedBonusRunning(recorder: BonusEvidenceRecorder()) { _ in }

        harness.coach.model.onDisappear()
        harness.coach.model.onDisappear()

        XCTAssertEqual(harness.recorder.evidence.count, 1)
        XCTAssertEqual(harness.recorder.evidence.first?.bonus, BonusRecord(offered: .seconds(5), accepted: true),
                       "Nothing was held yet, so nothing is reported, not even zero.")
    }

    func testClosingTheScreenDuringARunningSelfReportedBonusInventsNoReps() {
        let exercise = selfReported(target: 5)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        finishMainItem(harness)
        harness.model.rateEffort(.easy)
        harness.model.acceptBonus()
        harness.model.send(.start)
        XCTAssertEqual(harness.model.session.phase, .exercising)

        harness.model.onDisappear()
        harness.model.onDisappear()

        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(recorder.evidence.first?.bonus, BonusRecord(offered: .reps(1), accepted: true),
                       "Nobody said the rep was done.")
    }

    func testClosingTheScreenDuringARunningCameraBonusKeepsTheCountUnconfirmed() {
        let wallPushUp = WallPushUpExercise.definition()
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [wallPushUp], launch: launch(exercise: wallPushUp, dose: .reps(1)),
                                  recorder: recorder)
        open(harness)
        var time = 0.0
        driveSet(harness, exercise: wallPushUp, time: &time)
        harness.model.rateEffort(.easy)
        harness.model.acceptBonus()
        harness.model.send(.start)
        XCTAssertEqual(harness.model.session.phase, .exercising)

        harness.model.onDisappear()
        harness.model.onDisappear()

        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(recorder.evidence.first?.bonus, BonusRecord(offered: .reps(1), accepted: true),
                       "A camera count nobody rated is not a confirmed amount.")
    }

    func testTheWorkoutEndingAfterTheSnapshotPathStillRecordsTheBonusOnce() {
        // Ending first, then closing: the end transition recorded the seconds, so the close has nothing left to flush.
        let harness = timedBonusRunning(recorder: BonusEvidenceRecorder()) { $0.scheduler.advance(by: 3) }

        harness.coach.model.send(.endWorkout)
        harness.coach.model.onDisappear()
        harness.coach.model.onDisappear()

        XCTAssertEqual(harness.recorder.evidence.count, 1)
        XCTAssertEqual(harness.recorder.evidence.first?.bonus,
                       BonusRecord(offered: .seconds(5), accepted: true, completed: .seconds(3)))
    }

    // MARK: - Review round: skipping partway through the bonus

    func testSkippingAPartiallyDoneTimedBonusKeepsItsWorkInEvidenceAndInTheSavedRecord() throws {
        // Revert check (review 2): a record that drops the partial seconds leaves no bonus entry in history.
        let exercise = hold(seconds: 20)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .seconds(20)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.scheduler.advance(by: 21)
        harness.model.rateEffort(.easy)
        harness.model.acceptBonus()
        harness.model.send(.start)
        harness.scheduler.advance(by: 3)

        harness.model.send(.nextExercise)

        let card = try XCTUnwrap(harness.model.effortCard)
        XCTAssertTrue(card.isBonus)
        XCTAssertEqual(card.amount, 3)
        XCTAssertEqual(card.setCount, 1, "The three seconds are counted once, not once from the record and once again.")
        harness.model.rateEffort(.okay)

        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(evidence.bonus,
                       BonusRecord(offered: .seconds(5), accepted: true, completed: .seconds(3), effort: .okay))

        let record = try savedRecord(harness)
        XCTAssertEqual(record.entries.map(\.name), [exercise.displayName, "Bonus: \(exercise.displayName)"])
        let bonusEntry = try XCTUnwrap(record.entries.last)
        XCTAssertEqual(bonusEntry.sets.map(\.seconds), [3], "The seconds held are saved as bonus work.")
        XCTAssertNil(bonusEntry.outcome, "A bonus is never labeled skipped.")
        XCTAssertFalse(record.entries.contains { $0.outcome == .skipped })
        let stats = WorkoutCompletionStats(record: record)
        XCTAssertEqual(stats.exerciseRows.map(\.isBonus), [false, true])
        XCTAssertEqual(stats.exerciseRows.last?.summary, "Bonus: \(exercise.displayName) — 1 set · 3 s",
                       "No \"Skipped\" label on work the user did.")
        XCTAssertEqual(stats.exerciseCount, 1)
        let recordedWeights = harness.model.session.planRecords[insertedBonusID(in: harness)]?.setWeights.count
        XCTAssertEqual(recordedWeights, 1, "The weight list stays parallel to the sets.")
    }

    func testSkippingATimedBonusBeforeAnySecondsRunStillLeavesNoEntry() throws {
        let exercise = hold(seconds: 20)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .seconds(20)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.scheduler.advance(by: 21)
        harness.model.rateEffort(.easy)
        harness.model.acceptBonus()
        harness.model.send(.start)

        harness.model.send(.nextExercise)

        XCTAssertNil(harness.model.effortCard, "Nothing was done, so there is nothing to rate.")
        XCTAssertEqual(recorder.evidence.first?.bonus, BonusRecord(offered: .seconds(5), accepted: true))
        let record = try savedRecord(harness)
        XCTAssertEqual(record.entries.map(\.name), [exercise.displayName], "A zero-work bonus stays omitted.")
    }

    func testSkippingAnOrdinaryTimedItemMidHoldStillKeepsFinishedSetsOnly() throws {
        // The partial seconds reach the evidence through the detector, as before; the saved occurrence is unchanged.
        let exercise = hold(seconds: 20)
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .seconds(20)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.scheduler.advance(by: 7)

        harness.model.send(.nextExercise)

        let occurrence = try XCTUnwrap(harness.model.session.planRecords[mainID])
        XCTAssertEqual(occurrence.outcome, .skipped)
        XCTAssertEqual(occurrence.setReps, [], "An ordinary occurrence keeps finished sets only.")
        XCTAssertEqual(harness.model.effortCard?.amount, 7, "The card still opens at the seconds held.")
        XCTAssertEqual(harness.model.effortCard?.setCount, 1)
    }

    func testChoosingAnotherExerciseDuringAPartialTimedBonusKeepsItsWorkToo() throws {
        let exercise = hold(seconds: 20)
        let other = WallPushUpExercise.definition()
        let recorder = BonusEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise, other], launch: launch(exercise: exercise, dose: .seconds(20)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.scheduler.advance(by: 21)
        harness.model.rateEffort(.easy)
        harness.model.acceptBonus()
        harness.model.send(.start)
        harness.scheduler.advance(by: 3)

        harness.model.send(.changeExercise)
        harness.model.send(.chooseExercise(other.id))

        let card = try XCTUnwrap(harness.model.effortCard)
        XCTAssertTrue(card.isBonus)
        XCTAssertEqual(card.amount, 3)
        XCTAssertEqual(card.setCount, 1)
        harness.model.rateEffort(.easy)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(recorder.evidence.first?.bonus,
                       BonusRecord(offered: .seconds(5), accepted: true, completed: .seconds(3), effort: .easy))
        let record = try savedRecord(harness)
        XCTAssertEqual(record.entries.last?.sets.map(\.seconds), [3])
        XCTAssertNil(record.entries.last?.outcome)
    }

    // MARK: - Fixtures

    private let bonusID = BonusRepsTests.uuid(0x54)

    /// A Today's Session timed hold whose five-second bonus has been accepted and started. `prepare` then lets time
    /// pass (or not) before a test closes the screen.
    private func timedBonusRunning(recorder: BonusEvidenceRecorder,
                                   prepare: (WorkoutCoachHarness) -> Void) -> (coach: WorkoutCoachHarness, recorder: BonusEvidenceRecorder) {
        let exercise = hold(seconds: 20)
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .seconds(20)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.scheduler.advance(by: 21)
        harness.model.rateEffort(.easy)
        harness.model.acceptBonus()
        harness.model.send(.start)
        prepare(harness)
        return (harness, recorder)
    }

    /// The id of the bonus occurrence the model inserted.
    private func insertedBonusID(in harness: WorkoutCoachHarness) -> UUID {
        harness.model.session.plan?.items.first(where: \.isBonus)?.id ?? bonusID
    }

    private static func uuid(_ number: Int) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, UInt8(truncatingIfNeeded: number)))
    }

    private func selfReported(target: Int) -> ExerciseDefinition {
        var copy = ShoulderPressExercise.definition()
        copy.tracking = .selfReported
        copy.targetReps = target...target
        copy.autoCompleteReps = target
        copy.targetRangeAnnouncementReps = nil
        copy.sets = 1
        return copy
    }

    private func hold(seconds: Int) -> ExerciseDefinition {
        var copy = selfReported(target: seconds)
        copy.doseUnit = .seconds
        return copy
    }

    /// Today's Session as the coordinator would prepare it, with prescription items that offer a bonus.
    private func launch(exercise: ExerciseDefinition, dose: Dose, withSample: Bool = false, reducedRange: Bool = false,
                        offersBonus: Bool = true) -> TodaySessionLaunch {
        var items = [AdaptivePlanItem(itemID: mainID, role: .main, family: .push,
                                      rungDose: RungDose(variant: reducedRange ? shallow : wall, dose: dose),
                                      exerciseID: exercise.id, reducedRange: reducedRange)]
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
        // Both items say they offer a bonus, so a sample not earning one shows the role is what decides.
        let prescription = Prescription(
            id: prescriptionID, issuedAt: Date(timeIntervalSince1970: 900), kind: .todaySession, policyVersion: .v1,
            catalogVersion: "test",
            items: items.map { PrescriptionItem(id: $0.itemID, family: $0.family, target: $0.rungDose, role: $0.role,
                                                offersBonus: offersBonus) },
            rationale: "Test")
        return TodaySessionLaunch(prescription: prescription,
                                  plan: WorkoutPlan(id: AdaptiveTrainingCoordinator.todaySessionPlanID,
                                                    name: "Today's Session", items: planItems),
                                  items: items)
    }

    private func makeHarness(exercises: [ExerciseDefinition], launch: TodaySessionLaunch?, plan: WorkoutPlan? = nil,
                             recorder: BonusEvidenceRecorder) -> WorkoutCoachHarness {
        WorkoutCoachHarness.make(preferences: InMemoryPreferences(), exercises: exercises,
                                 initialExercise: exercises.first?.id ?? .shoulderPress,
                                 plan: launch?.plan ?? plan, adaptive: recorder, todayLaunch: launch)
    }

    private func open(_ harness: WorkoutCoachHarness) {
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
    }

    /// A self-reported or timed item's first set, done by the user.
    private func finishMainItem(_ harness: WorkoutCoachHarness) {
        harness.model.send(.start)
        harness.model.send(.nextSet)
    }

    /// Frames of the guide's own demonstration at the camera's real cadence, until the set ends.
    private func driveSet(_ harness: WorkoutCoachHarness, exercise: ExerciseDefinition, time: inout Double) {
        func frame() {
            harness.scheduler.advance(by: 0.1)
            time += 0.1
            harness.camera.emit(.frame(ReadyPoseFixtures.demoFrame(exercise, motionTime: time, at: time)))
        }
        for _ in 0..<10 { frame() }
        if harness.model.session.phase != .exercising { harness.model.send(.start) }
        var steps = 0
        while harness.model.session.phase == .exercising, steps < 600 {
            frame()
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

    /// The workout as it would be saved right now.
    private func savedRecord(_ harness: WorkoutCoachHarness) throws -> WorkoutRecord {
        try XCTUnwrap(WorkoutRecord(session: harness.model.session, startedAt: Date(timeIntervalSince1970: 0),
                                    endedAt: Date(timeIntervalSince1970: 30), id: harness.model.workoutID))
    }

    /// A Today's Session of a shallow wall push-up main item (and optionally the sample), with the main item done or
    /// skipped, driven through the reducer alone.
    private func makeSession(withSample: Bool, skipMain: Bool = false) -> WorkoutSession {
        var items = [WorkoutPlanItem(id: mainID, exerciseID: .wallPushUp, sets: 1, targetReps: 3...3, reducedRange: true)]
        if withSample {
            items.append(WorkoutPlanItem(id: sampleID, exerciseID: .wallPushUp, sets: 1, targetReps: 1...1, isOptional: true))
        }
        let plan = WorkoutPlan(id: AdaptiveTrainingCoordinator.todaySessionPlanID, name: "Today's Session", items: items)
        var session = WorkoutSession(exercises: ExerciseCatalog.all, initialExercise: .wallPushUp, plan: plan)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: 1)
        _ = session.handle(.command(.start), at: 2)
        _ = session.handle(.command(skipMain ? .nextExercise : .nextSet), at: 3)
        return session
    }

    private func finished(amounts: [Int], target: Int, result: FinishedWorkoutItem.Result,
                          tracking: FinishedWorkoutItem.Tracking = .selfReported, trackingLost: Bool = false,
                          isBonus: Bool = false) -> FinishedWorkoutItem {
        FinishedWorkoutItem(planItemID: isBonus ? bonusID : mainID, exerciseID: .wallPushUp, reducedRange: false,
                            unit: .reps, tracking: tracking, setAmounts: amounts, target: target, result: result,
                            trackingLost: trackingLost, isBonus: isBonus)
    }

    // MARK: - Engine rig

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private func date(day: Int, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour)) ?? Date(timeIntervalSince1970: 0)
    }

    private func calibration(_ family: MovementFamilyID, at variant: VariantID, dose: Dose) -> CalibrationSessionRecord {
        CalibrationSessionRecord(id: UUID(uuid: (0xCA, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 10)),
                                 kind: .initial, startedAt: date(day: 10, hour: 9), endedAt: date(day: 10, hour: 9),
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
        let recognizer: BonusScriptedRecognizer
        let scheduler: ManualScheduler
        let box: VoiceBox

        var answers: [BonusAnswer] { box.answers }
        var commands: [WorkoutCommand] { box.commands }
        var heard: [String] { box.heard }

        /// Time passes, so a transcript can settle.
        func advance(_ seconds: TimeInterval) { scheduler.advance(by: seconds) }
    }

    private final class VoiceBox {
        var answers: [BonusAnswer] = []
        var commands: [WorkoutCommand] = []
        var heard: [String] = []
    }

    private func makeVoiceRig(parser: any VoiceCommandParsing = BonusEveryPhraseIsPause()) -> VoiceRig {
        let recognizer = BonusScriptedRecognizer()
        let clock = ManualClock(now: 10)
        let scheduler = ManualScheduler(clock: clock)
        let controller = WorkoutVoiceController(recognizer: recognizer, parser: parser,
                                                permissions: BonusGrantedPermissions(), audio: FakeAudioSession(),
                                                clock: { clock.now }, scheduler: scheduler)
        let box = VoiceBox()
        controller.onBonus = { box.answers.append($0) }
        controller.onCommand = { box.commands.append($0) }
        controller.onHeard = { box.heard.append($0) }
        controller.enable()
        return VoiceRig(controller: controller, recognizer: recognizer, scheduler: scheduler, box: box)
    }
}

/// Records evidence and answers active-rung lookups from a table the test fills in.
@MainActor
private final class BonusEvidenceRecorder: AdaptiveEvidenceRecording {
    private(set) var evidence: [AdaptiveEvidence] = []
    private var rungs: [String: ActiveRung] = [:]

    func setRung(_ rung: ActiveRung, for exerciseID: ExerciseID, reducedRange: Bool = false) {
        rungs["\(exerciseID.rawValue)|\(reducedRange)"] = rung
    }

    func activeRung(for exerciseID: ExerciseID, reducedRange: Bool) -> ActiveRung? {
        rungs["\(exerciseID.rawValue)|\(reducedRange)"]
    }

    func record(_ evidence: AdaptiveEvidence) {
        self.evidence.append(evidence)
    }
}

/// A command parser that turns every transcript into Pause, so any bonus phrase that reaches it is visible.
private struct BonusEveryPhraseIsPause: VoiceCommandParsing {
    var vocabulary: [String] { [] }

    func parse(_ transcript: String) -> VoiceCommandMatch? {
        VoiceCommandMatch(command: .pause, phrase: transcript, isPrefixOfLongerPhrase: false)
    }
}

private final class BonusScriptedRecognizer: SpeechRecognizing {
    var onTranscript: ((String, Bool) -> Void)?
    var onStateChanged: ((SpeechRecognizerState) -> Void)?
    private(set) var restartCount = 0

    func setContextualStrings(_ strings: [String]) {}
    func start() {}
    func stop() {}
    func restartTask() { restartCount += 1 }
    func reconfigureInput() {}
    func rebuild() {}

    /// A transcript the recognizer reports. A final one runs a match at once; a partial one is still streaming.
    func hear(_ text: String, final: Bool = true) {
        onTranscript?(text, final)
    }
}

@MainActor
private struct BonusGrantedPermissions: VoicePermissionProviding {
    var microphone: VoicePermissionStatus { .granted }
    var speechRecognition: VoicePermissionStatus { .granted }
    func requestMicrophone(_ completion: @escaping @MainActor (Bool) -> Void) { completion(true) }
    func requestSpeechRecognition(_ completion: @escaping @MainActor (Bool) -> Void) { completion(true) }
}
