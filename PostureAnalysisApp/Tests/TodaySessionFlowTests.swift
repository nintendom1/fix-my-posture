import AdaptiveTraining
import XCTest
@testable import PostureAnalysisApp

/// Today's Session end to end through the coach model: the effort card, the evidence it records, and the saved workout.
@MainActor
final class TodaySessionFlowTests: XCTestCase {
    private let prescriptionID = TodaySessionFlowTests.uuid(0x31)
    private let mainID = TodaySessionFlowTests.uuid(0x32)
    private let sampleID = TodaySessionFlowTests.uuid(0x33)
    private let shallow = VariantID(rawValue: "push.wall_push_up.shallow")
    private let wall = VariantID(rawValue: "push.wall_push_up")

    // MARK: - The card after a finished Today item

    func testAOneRepCameraItemOpensTheCardAndEasyRecordsAcceptedEvidence() throws {
        let wallPushUp = WallPushUpExercise.definition()
        let recorder = FakeEvidenceRecorder()
        let launch = launch(exercise: wallPushUp, dose: .reps(1))
        let harness = makeHarness(exercises: [wallPushUp], launch: launch, recorder: recorder)
        open(harness)

        driveOneRep(harness, exercise: wallPushUp)

        XCTAssertEqual(harness.model.session.phase, .exerciseComplete)
        let card = try XCTUnwrap(harness.model.effortCard, "A finished Today item asks how it was.")
        XCTAssertEqual(card.amount, 1)
        XCTAssertEqual(card.unit, .reps)
        XCTAssertEqual(card.amountLabel, "1 rep")
        XCTAssertTrue(recorder.evidence.isEmpty, "Nothing is recorded until the card closes.")

        harness.model.rateEffort(.easy)

        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertNil(harness.model.effortCard)
        XCTAssertEqual(evidence.id, card.id)
        XCTAssertEqual(evidence.source, .adaptive)
        XCTAssertEqual(evidence.prescriptionID, prescriptionID)
        XCTAssertEqual(evidence.prescriptionItemID, mainID)
        XCTAssertEqual(evidence.workoutID, harness.model.workoutID)
        XCTAssertEqual(evidence.family, .push)
        XCTAssertEqual(evidence.variant, shallow)
        XCTAssertEqual(evidence.prescribed, .reps(1))
        XCTAssertEqual(evidence.confirmed, .reps(1))
        XCTAssertEqual(evidence.confirmation, .trackerAccepted)
        XCTAssertEqual(evidence.effort, .easy)
        XCTAssertEqual(evidence.completion, .completed)
        XCTAssertEqual(evidence.tracker, TrackerObservation(status: .tracked, observed: .reps(1)))
    }

    func testSkippingTheCardRecordsUnratedEvidence() throws {
        let wallPushUp = WallPushUpExercise.definition()
        let recorder = FakeEvidenceRecorder()
        let harness = makeHarness(exercises: [wallPushUp], launch: launch(exercise: wallPushUp, dose: .reps(1)),
                                  recorder: recorder)
        open(harness)
        driveOneRep(harness, exercise: wallPushUp)
        XCTAssertNotNil(harness.model.effortCard)

        harness.model.skipEffort()

        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertNil(harness.model.effortCard)
        XCTAssertNil(evidence.effort)
        XCTAssertEqual(evidence.confirmation, .none)
        XCTAssertNil(evidence.confirmed)
        XCTAssertEqual(evidence.tracker.observed, .reps(1), "What the camera counted is still recorded.")
    }

    func testAdjustingTheAmountRecordsWhatTheUserConfirmed() throws {
        let exercise = selfReported(target: 5)
        let recorder = FakeEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextSet)
        XCTAssertEqual(harness.model.effortCard?.amount, 5, "A self-reported set opens with the recorded amount.")

        harness.model.adjustEffortAmount(by: -1)
        harness.model.adjustEffortAmount(by: -1)
        XCTAssertEqual(harness.model.effortCard?.amount, 3)
        XCTAssertEqual(harness.model.effortCard?.isAdjusted, true)
        harness.model.rateEffort(.okay)

        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(evidence.confirmed, .reps(3))
        XCTAssertEqual(evidence.confirmation, .user)
        XCTAssertEqual(evidence.completion, .stoppedEarly)
        XCTAssertEqual(evidence.effort, .okay)
        XCTAssertEqual(evidence.tracker, .notTracked)
    }

    func testTheAmountNeverGoesBelowZeroAndStepsByTheUnit() {
        var reps = EffortCardState(id: UUID(), unit: .reps, setCount: 1, amount: 1)
        reps.adjust(by: -1)
        reps.adjust(by: -1)
        XCTAssertEqual(reps.amount, 0)
        XCTAssertEqual(reps.amountLabel, "0 reps")
        reps.adjust(by: 2)
        XCTAssertEqual(reps.amount, 2)

        var seconds = EffortCardState(id: UUID(), unit: .seconds, setCount: 1, amount: 20)
        seconds.adjust(by: 1)
        XCTAssertEqual(seconds.amount, 25)
        XCTAssertEqual(seconds.amountLabel, "25 s")
        seconds.adjust(by: -10)
        XCTAssertEqual(seconds.amount, 0)
    }

    func testStartingTheNextSetWithTheCardOpenClosesItUnratedAndDoesNotBlockTheSet() throws {
        // Revert check (d): if an open card blocked the next set, the session would stay resting and this fails.
        let exercise = selfReported(target: 5)
        let recorder = FakeEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5), withSample: true),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextSet)
        XCTAssertEqual(harness.model.session.phase, .resting, "The optional sample is next, after a rest.")
        XCTAssertNotNil(harness.model.effortCard, "The card is open while rest keeps running.")

        harness.scheduler.advance(by: 5)
        XCTAssertEqual(harness.model.session.phase, .resting, "The card doesn't pause the rest.")
        XCTAssertNotNil(harness.model.effortCard)

        harness.model.send(.start)

        XCTAssertEqual(harness.model.session.phase, .exercising, "Starting the sample isn't blocked by the card.")
        XCTAssertNil(harness.model.effortCard)
        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(evidence.prescriptionItemID, mainID)
        XCTAssertNil(evidence.effort, "Closed without an answer, it is recorded unrated.")
    }

    func testStartingTheNextSetByVoiceAlsoClosesTheCard() throws {
        let exercise = selfReported(target: 5)
        let recorder = FakeEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5), withSample: true),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextSet)

        harness.voice.emit(.start)

        XCTAssertEqual(harness.model.session.phase, .exercising)
        XCTAssertNil(harness.model.effortCard)
        XCTAssertEqual(recorder.evidence.count, 1)
    }

    func testTheCompletionScreenWaitsForTheLastCard() throws {
        let exercise = selfReported(target: 5)
        let recorder = FakeEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextSet)

        XCTAssertEqual(harness.model.session.phase, .exerciseComplete)
        XCTAssertTrue(harness.model.hud.visual.showsCompletionCard, "The reducer is done.")
        XCTAssertFalse(harness.model.showsCompletionCard, "But the completion screen waits for the answer.")

        harness.model.skipEffort()

        XCTAssertTrue(harness.model.showsCompletionCard)
    }

    func testASkippedHarderSampleRecordsNotAttemptedEvidence() throws {
        let exercise = selfReported(target: 5)
        let recorder = FakeEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5), withSample: true),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextSet)
        harness.model.rateEffort(.okay)
        XCTAssertEqual(recorder.evidence.count, 1)

        harness.model.send(.nextExercise)

        XCTAssertEqual(harness.model.session.phase, .exerciseComplete)
        let card = try XCTUnwrap(harness.model.effortCard)
        XCTAssertEqual(card.amount, 0, "A skipped item opens at zero.")
        harness.model.skipEffort()

        XCTAssertEqual(recorder.evidence.count, 2)
        let sample = try XCTUnwrap(recorder.evidence.last)
        XCTAssertEqual(sample.prescriptionItemID, sampleID)
        XCTAssertEqual(sample.completion, .notAttempted)
        XCTAssertEqual(sample.confirmation, .none)
        XCTAssertNil(sample.confirmed)
        XCTAssertEqual(sample.tracker, .notTracked)
        XCTAssertEqual(sample.variant, wall)
    }

    func testASecondFinishedItemClosesTheFirstCardUnrated() throws {
        let exercise = selfReported(target: 5)
        let recorder = FakeEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5), withSample: true),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextExercise)
        XCTAssertEqual(harness.model.effortCard?.amount, 0)

        harness.model.send(.nextExercise)

        XCTAssertEqual(recorder.evidence.count, 1, "The first item's card closed unrated.")
        XCTAssertEqual(recorder.evidence.first?.prescriptionItemID, mainID)
        XCTAssertEqual(recorder.evidence.first?.completion, .notAttempted)
        XCTAssertNotNil(harness.model.effortCard, "The sample's own card is open now.")
    }

    func testTimedHoldsRecordSecondsEvidence() throws {
        let exercise = hold(seconds: 20)
        let recorder = FakeEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .seconds(20)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)

        harness.scheduler.advance(by: 21)

        let card = try XCTUnwrap(harness.model.effortCard)
        XCTAssertEqual(card.unit, .seconds)
        XCTAssertEqual(card.amount, 20)
        XCTAssertEqual(card.amountLabel, "20 s")
        harness.model.rateEffort(.easy)

        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(evidence.confirmed, .seconds(20))
        XCTAssertEqual(evidence.setAmounts, [.seconds(20)])
        XCTAssertEqual(evidence.prescribed, .seconds(20))
        XCTAssertEqual(evidence.confirmation, .user)
        XCTAssertEqual(evidence.tracker, .notTracked)
        XCTAssertEqual(evidence.completion, .completed)
    }

    func testEndingTheWorkoutDuringATodayItemRecordsItEndedWithNoCard() throws {
        let exercise = hold(seconds: 20)
        let recorder = FakeEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .seconds(20)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.scheduler.advance(by: 7)

        harness.model.send(.endWorkout)

        XCTAssertEqual(harness.model.session.phase, .ended)
        XCTAssertNil(harness.model.effortCard, "The workout is over, so nothing is asked.")
        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(evidence.completion, .endedWorkout)
        XCTAssertNil(evidence.effort)
        XCTAssertEqual(evidence.prescriptionItemID, mainID)
    }

    func testEndingTheWorkoutWithTheCardOpenRecordsItUnrated() throws {
        let exercise = selfReported(target: 5)
        let recorder = FakeEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextSet)
        XCTAssertNotNil(harness.model.effortCard)

        harness.model.send(.endWorkout)

        XCTAssertNil(harness.model.effortCard)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertNil(recorder.evidence.first?.effort)
    }

    func testClosingTheScreenWithTheCardOpenRecordsItUnratedOnce() throws {
        let exercise = selfReported(target: 5)
        let recorder = FakeEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextSet)

        harness.model.onDisappear()
        harness.model.onDisappear()

        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertNil(recorder.evidence.first?.effort)
    }

    // MARK: - Voice

    func testASpokenOkayRatesTheCardAndTheCardAsksTheVoiceControllerToListenForIt() throws {
        let exercise = selfReported(target: 5)
        let recorder = FakeEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        XCTAssertFalse(harness.voice.acceptsEffortFeedback, "Effort phrases are only listened for while the card is open.")
        harness.model.send(.nextSet)
        XCTAssertTrue(harness.voice.acceptsEffortFeedback)

        harness.voice.emitHeard("okay")
        harness.voice.emitEffort(.okay)

        XCTAssertFalse(harness.voice.acceptsEffortFeedback)
        XCTAssertNil(harness.model.effortCard)
        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(evidence.effort, .okay)
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete, "An effort phrase never runs as a command.")
    }

    // MARK: - Manual work

    func testARoutineExerciseThatIsTheActiveRungAsksAndRecordsManualEvidence() throws {
        let exercise = selfReported(target: 5)
        let recorder = FakeEvidenceRecorder()
        recorder.setRung(ActiveRung(family: .push, rungDose: RungDose(variant: wall, dose: .reps(5))), for: exercise.id)
        let routine = WorkoutPlan(id: UUID(), name: "My routine", items: [
            WorkoutPlanItem(id: TodaySessionFlowTests.uuid(0x41), exerciseID: exercise.id, sets: 1, targetReps: 5...5)
        ])
        let harness = makeHarness(exercises: [exercise], launch: nil, plan: routine, recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextSet)

        XCTAssertNotNil(harness.model.effortCard, "A routine exercise that is the current rung of an active family asks too.")
        harness.model.rateEffort(.easy)

        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(evidence.source, .manual)
        XCTAssertNil(evidence.prescriptionID)
        XCTAssertNil(evidence.prescriptionItemID)
        XCTAssertNil(evidence.prescribed)
        XCTAssertEqual(evidence.family, .push)
        XCTAssertEqual(evidence.variant, wall)
        XCTAssertEqual(evidence.effort, .easy)
        XCTAssertEqual(evidence.confirmed, .reps(5))
        XCTAssertEqual(evidence.workoutID, harness.model.workoutID)
    }

    func testAQuickStartExerciseThatIsTheActiveRungAsksToo() throws {
        let exercise = selfReported(target: 5)
        let recorder = FakeEvidenceRecorder()
        recorder.setRung(ActiveRung(family: .push, rungDose: RungDose(variant: wall, dose: .reps(5))), for: exercise.id)
        let harness = makeHarness(exercises: [exercise], launch: nil, recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextSet)

        harness.model.rateEffort(.okay)

        XCTAssertEqual(recorder.evidence.first?.source, .manual)
    }

    func testAnExerciseInAnInactiveFamilyAsksNothing() {
        let exercise = selfReported(target: 5)
        let recorder = FakeEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: nil, recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextSet)

        XCTAssertEqual(harness.model.session.phase, .exerciseComplete)
        XCTAssertNil(harness.model.effortCard)
        XCTAssertTrue(recorder.evidence.isEmpty)
        XCTAssertTrue(harness.model.showsCompletionCard)
    }

    func testAWorkoutWithNoEngineNeverAsks() {
        let exercise = selfReported(target: 5)
        let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), exercises: [exercise],
                                               initialExercise: exercise.id)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextSet)

        XCTAssertNil(harness.model.effortCard)
        XCTAssertTrue(harness.model.showsCompletionCard)
    }

    func testASkippedRoutineExerciseWithNoWorkAsksNothing() {
        let exercise = selfReported(target: 5)
        let recorder = FakeEvidenceRecorder()
        recorder.setRung(ActiveRung(family: .push, rungDose: RungDose(variant: wall, dose: .reps(5))), for: exercise.id)
        let routine = WorkoutPlan(id: UUID(), name: "My routine", items: [
            WorkoutPlanItem(id: TodaySessionFlowTests.uuid(0x41), exerciseID: exercise.id, sets: 1, targetReps: 5...5),
            WorkoutPlanItem(id: TodaySessionFlowTests.uuid(0x42), exerciseID: exercise.id, sets: 1, targetReps: 5...5)
        ])
        let harness = makeHarness(exercises: [exercise], launch: nil, plan: routine, recorder: recorder)
        open(harness)
        harness.model.send(.start)

        harness.model.send(.nextExercise)

        XCTAssertNil(harness.model.effortCard)
        XCTAssertTrue(recorder.evidence.isEmpty)
    }

    // MARK: - The saved workout

    func testAOneRepTodaySessionSavesAndReadsBackLikeAnyWorkout() throws {
        let exercise = selfReported(target: 1)
        let recorder = FakeEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(1)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextSet)
        harness.model.skipEffort()

        let record = try XCTUnwrap(WorkoutRecord(session: harness.model.session, startedAt: Date(timeIntervalSince1970: 100),
                                                 endedAt: Date(timeIntervalSince1970: 140), id: harness.model.workoutID),
                                   "One rep is a workout worth saving.")
        XCTAssertEqual(record.planID, AdaptiveTrainingCoordinator.todaySessionPlanID)
        XCTAssertEqual(record.planName, "Today's Session")
        XCTAssertEqual(record.totalReps, 1)
        XCTAssertEqual(record.entries.map(\.outcome), [.completed])

        let container = try AppModelContainer.make(inMemory: true)
        let repository = SwiftDataWorkoutHistoryRepository(context: container.mainContext)
        try WorkoutHistorySaver.save(record, using: repository, preferences: InMemoryPreferences())

        XCTAssertEqual(try repository.list(), [record])
        XCTAssertEqual(WorkoutCompletionStats(record: record).totalReps, 1)
        XCTAssertEqual(recorder.evidence.first?.workoutID, record.id, "Evidence stays linked to the saved workout.")
    }

    func testRoutineRotationNeverCountsATodaySessionRecordAsARoutine() {
        let named = SavedExerciseSetRecord(set: SavedExerciseSet(name: "Today's Session", items: []),
                                           createdAt: Date(timeIntervalSince1970: 10),
                                           updatedAt: Date(timeIntervalSince1970: 10))
        let other = SavedExerciseSetRecord(set: SavedExerciseSet(name: "Other", items: []),
                                           createdAt: Date(timeIntervalSince1970: 20),
                                           updatedAt: Date(timeIntervalSince1970: 20))
        let today = todayRecord(endedAt: Date(timeIntervalSince1970: 500))

        XCTAssertNil(RoutineRotation.lastDone(routine: named.set, records: [today]),
                     "Even a routine named like the session doesn't claim it.")
        XCTAssertNil(RoutineRotation.lastDone(routine: other.set, records: [today]))
        XCTAssertEqual(RoutineRotation.upNext(routines: [named, other], records: [today], override: nil)?.id, named.set.id,
                       "A Today's Session record doesn't make a routine look done.")
    }

    func testSavingATodaySessionKeepsTheUpNextOverride() throws {
        // Revert check (c): clearing the override for Today's Session makes this fail.
        let preferences = InMemoryPreferences()
        let override = UUID()
        preferences.upNextOverride = override
        let repository = RecordingHistoryRepository()

        try WorkoutHistorySaver.save(todayRecord(endedAt: Date(timeIntervalSince1970: 500)), using: repository,
                                     preferences: preferences)

        XCTAssertEqual(repository.saved.count, 1)
        XCTAssertEqual(preferences.upNextOverride, override)
    }

    func testSavingARoutineWorkoutStillClearsTheUpNextOverride() throws {
        let preferences = InMemoryPreferences()
        preferences.upNextOverride = UUID()
        let routine = WorkoutRecord(startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 60),
                                    planID: UUID(), planName: "Routine",
                                    entries: [WorkoutRecordEntry(exerciseID: .shoulderPress, name: "Shoulder Press",
                                                                 outcome: .completed, sets: [RecordedSet(reps: 8)])])

        try WorkoutHistorySaver.save(routine, using: RecordingHistoryRepository(), preferences: preferences)

        XCTAssertNil(preferences.upNextOverride)
    }

    // MARK: - Completion copy

    func testATinyTodaySessionHasItsOwnCompletionCopy() {
        let state = WorkoutCompleteState(record: todayRecord(endedAt: Date(timeIntervalSince1970: 140), startedAt: 100))

        XCTAssertEqual(state.title, "Today's session complete")
        XCTAssertEqual(state.subtitle, "Today's Session · done")
        XCTAssertFalse(state.subtitle.contains("every set done"))
        XCTAssertEqual(state.stats.durationLabel, "40 s", "A short session shows its actual length, not <1m.")
        XCTAssertEqual(state.stats.totalReps, 1)
        XCTAssertEqual(state.stats.exerciseRows.map(\.amountLabel), ["1 rep"])
    }

    func testATodaySessionUnderASecondReadsDoneAndALongOneKeepsMinutes() {
        XCTAssertEqual(WorkoutCompletionStats(record: todayRecord(endedAt: Date(timeIntervalSince1970: 100.4),
                                                                  startedAt: 100)).durationLabel, "Done")
        XCTAssertEqual(WorkoutCompletionStats(record: todayRecord(endedAt: Date(timeIntervalSince1970: 220),
                                                                  startedAt: 100)).durationLabel, "2m")
        XCTAssertEqual(WorkoutCompletionStats(record: todayRecord(endedAt: Date(timeIntervalSince1970: 159),
                                                                  startedAt: 100)).durationLabel, "59 s")
    }

    func testASkippedOptionalSampleReadsOptionalSkipped() throws {
        var record = todayRecord(endedAt: Date(timeIntervalSince1970: 140), startedAt: 100)
        record.entries.append(WorkoutRecordEntry(exerciseID: .inclinePushUp, name: "Incline Push-Up", outcome: .skipped,
                                                 sets: []))

        let rows = WorkoutCompletionStats(record: record).exerciseRows

        XCTAssertEqual(rows.count, 2)
        let sample = try XCTUnwrap(rows.last)
        XCTAssertEqual(sample.name, "Optional: Incline Push-Up")
        XCTAssertTrue(sample.isOptional)
        XCTAssertEqual(sample.summary, "Optional: Incline Push-Up — Optional, skipped")
        XCTAssertFalse(try XCTUnwrap(rows.first).isOptional)
    }

    func testOtherWorkoutsKeepTheirExistingCopy() {
        let routine = WorkoutRecord(startedAt: Date(timeIntervalSince1970: 100), endedAt: Date(timeIntervalSince1970: 140),
                                    planID: UUID(), planName: "Upper Body",
                                    entries: [WorkoutRecordEntry(exerciseID: .shoulderPress, name: "Shoulder Press",
                                                                 outcome: .completed, sets: [RecordedSet(reps: 8)]),
                                              WorkoutRecordEntry(exerciseID: .hammerCurl, name: "Hammer Curl",
                                                                 outcome: .skipped, sets: [])])
        let state = WorkoutCompleteState(record: routine)
        XCTAssertEqual(state.title, "Workout complete!")
        XCTAssertEqual(state.subtitle, "Upper Body · workout complete")
        XCTAssertEqual(state.stats.durationLabel, "<1m")
        XCTAssertEqual(state.stats.exerciseRows.map(\.name), ["Shoulder Press", "Hammer Curl"])
        XCTAssertEqual(state.stats.exerciseRows.last?.summary, "Hammer Curl — Skipped")

        let finished = WorkoutRecord(startedAt: Date(timeIntervalSince1970: 100), endedAt: Date(timeIntervalSince1970: 100),
                                     planID: nil, planName: nil,
                                     entries: [WorkoutRecordEntry(exerciseID: .shoulderPress, name: "Shoulder Press",
                                                                  outcome: nil, sets: [RecordedSet(reps: 8)])])
        let plain = WorkoutCompleteState(record: finished)
        XCTAssertEqual(plain.subtitle, "Shoulder Press · every set done")
        XCTAssertEqual(plain.stats.durationLabel, "<1m")
    }

    func testAPlanOccurrenceShowsOptionalInItsName() {
        let optional = WorkoutPlanItem(id: UUID(), exerciseID: .wallPushUp, sets: 1, targetReps: 1...1, isOptional: true)
        let reduced = WorkoutPlanItem(id: UUID(), exerciseID: .wallPushUp, sets: 1, targetReps: 3...3, reducedRange: true)
        let plain = WorkoutPlanItem(id: UUID(), exerciseID: .wallPushUp, sets: 1, targetReps: 3...3)
        let exercise = WallPushUpExercise.definition()

        XCTAssertEqual(optional.label(for: exercise), "Optional: Wall Push-Up")
        XCTAssertEqual(reduced.label(for: exercise), "Shallow Wall Push-Up")
        XCTAssertEqual(plain.label(for: exercise), "Wall Push-Up")
        XCTAssertEqual(plain.label(for: nil), "Unavailable exercise")
    }

    // MARK: - Skipping after work (review finding 1)

    func testSkippingACameraItemAfterSomeRepsRecordsTheRepsAsStoppedEarly() throws {
        let wallPushUp = WallPushUpExercise.definition()
        let recorder = FakeEvidenceRecorder()
        let harness = makeHarness(exercises: [wallPushUp], launch: launch(exercise: wallPushUp, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        driveSet(harness, exercise: wallPushUp) { $0.session.repCount >= 2 }
        XCTAssertEqual(harness.model.session.repCount, 2)
        XCTAssertEqual(harness.model.session.phase, .exercising)

        harness.model.send(.nextExercise)

        XCTAssertEqual(harness.model.effortCard?.amount, 2, "The card opens at what the camera counted, not zero.")
        harness.model.rateEffort(.tooHard)
        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(evidence.completion, .stoppedEarly)
        XCTAssertEqual(evidence.confirmed, .reps(2))
        XCTAssertEqual(evidence.confirmation, .trackerAccepted)
        XCTAssertEqual(evidence.tracker, TrackerObservation(status: .tracked, observed: .reps(2)))
        XCTAssertEqual(evidence.effort, .tooHard)
        XCTAssertEqual(evidence.prescribed, .reps(5))
    }

    func testSkippingACameraItemBeforeAnyRepIsStillNotAttempted() throws {
        let wallPushUp = WallPushUpExercise.definition()
        let recorder = FakeEvidenceRecorder()
        let harness = makeHarness(exercises: [wallPushUp], launch: launch(exercise: wallPushUp, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        driveSet(harness, exercise: wallPushUp) { $0.session.phase == .exercising }
        XCTAssertEqual(harness.model.session.repCount, 0)

        harness.model.send(.nextExercise)
        XCTAssertEqual(harness.model.effortCard?.amount, 0)
        harness.model.skipEffort()

        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(evidence.completion, .notAttempted)
        XCTAssertEqual(evidence.tracker, .notTracked)
        XCTAssertNil(evidence.confirmed)
    }

    func testSkippingATimedHoldAfterSomeSecondsRecordsTheSecondsHeld() throws {
        let exercise = hold(seconds: 20)
        let recorder = FakeEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .seconds(20)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.scheduler.advance(by: 7)

        harness.model.send(.nextExercise)

        let card = try XCTUnwrap(harness.model.effortCard)
        XCTAssertEqual(card.unit, .seconds)
        XCTAssertEqual(card.amount, 7, "The timer's seconds are real work, not zero.")
        harness.model.rateEffort(.okay)
        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(evidence.completion, .stoppedEarly)
        XCTAssertEqual(evidence.confirmed, .seconds(7))
        XCTAssertEqual(evidence.confirmation, .user)
        XCTAssertEqual(evidence.tracker, .notTracked)
    }

    func testSkippingAnUnfinishedSelfReportedSetInventsNoWork() throws {
        let exercise = selfReported(target: 5)
        let recorder = FakeEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: launch(exercise: exercise, dose: .reps(5)),
                                  recorder: recorder)
        open(harness)
        harness.model.send(.start)

        harness.model.send(.nextExercise)

        XCTAssertEqual(harness.model.effortCard?.amount, 0, "Nobody said the reps were done.")
        harness.model.skipEffort()
        XCTAssertEqual(recorder.evidence.first?.completion, .notAttempted)
        XCTAssertNil(recorder.evidence.first?.confirmed)
    }

    func testTheDetectorReadsTheSetBeingSkippedFromBeforeTheSkip() throws {
        var exercise = hold(seconds: 20)
        exercise.sets = 1
        let item = WorkoutPlanItem(id: mainID, exerciseID: exercise.id, sets: 1, targetReps: 20...20)
        var session = WorkoutSession(exercises: [exercise], initialExercise: exercise.id,
                                     plan: WorkoutPlan(id: nil, name: "Plan", items: [item]))
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.command(.start), at: 1)
        let before = session

        _ = session.handle(.command(.nextExercise), at: 9)
        let found = FinishedItemDetector.finishedItems(before: before, after: session, at: 9)

        XCTAssertEqual(found.first?.setAmounts, [8])
        XCTAssertEqual(found.first?.result, .skipped)
    }

    // MARK: - Ending between sets (review finding 2)

    func testEndingDuringRestBetweenSetsRecordsTheFinishedSetsOfAManualExercise() throws {
        let exercise = twoSets(target: 5)
        let recorder = FakeEvidenceRecorder()
        recorder.setRung(ActiveRung(family: .push, rungDose: RungDose(variant: wall, dose: .reps(5))), for: exercise.id)
        let harness = makeHarness(exercises: [exercise], launch: nil, recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextSet)
        XCTAssertEqual(harness.model.session.phase, .resting)
        XCTAssertNil(harness.model.effortCard, "The first of two sets doesn't ask.")
        XCTAssertTrue(recorder.evidence.isEmpty)

        harness.model.send(.endWorkout)

        XCTAssertNil(harness.model.effortCard)
        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(evidence.source, .manual)
        XCTAssertEqual(evidence.completion, .endedWorkout)
        XCTAssertEqual(evidence.setAmounts, [.reps(5)])
        XCTAssertNil(evidence.effort)
        XCTAssertEqual(evidence.workoutID, harness.model.workoutID)
    }

    func testEndingDuringALaterSetBeforeDoneRecordsOnlyTheSetsThatFinished() throws {
        let exercise = twoSets(target: 5)
        let recorder = FakeEvidenceRecorder()
        recorder.setRung(ActiveRung(family: .push, rungDose: RungDose(variant: wall, dose: .reps(5))), for: exercise.id)
        let harness = makeHarness(exercises: [exercise], launch: nil, recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextSet)
        harness.model.send(.start)
        XCTAssertEqual(harness.model.session.phase, .exercising)

        harness.model.send(.endWorkout)

        let evidence = try XCTUnwrap(recorder.evidence.first)
        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(evidence.completion, .endedWorkout)
        XCTAssertEqual(evidence.setAmounts, [.reps(5)], "The set nobody marked done isn't invented.")
    }

    func testClosingTheScreenBetweenSetsRecordsOnceHoweverOftenItIsReported() throws {
        let exercise = twoSets(target: 5)
        let recorder = FakeEvidenceRecorder()
        recorder.setRung(ActiveRung(family: .push, rungDose: RungDose(variant: wall, dose: .reps(5))), for: exercise.id)
        let harness = makeHarness(exercises: [exercise], launch: nil, recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextSet)

        harness.model.onDisappear()
        harness.model.onDisappear()
        harness.model.send(.closeWorkout)

        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(recorder.evidence.first?.completion, .endedWorkout)
        XCTAssertEqual(recorder.evidence.first?.setAmounts, [.reps(5)])
    }

    func testEndingAndThenClosingTheScreenRecordsOnce() {
        let exercise = twoSets(target: 5)
        let recorder = FakeEvidenceRecorder()
        recorder.setRung(ActiveRung(family: .push, rungDose: RungDose(variant: wall, dose: .reps(5))), for: exercise.id)
        let harness = makeHarness(exercises: [exercise], launch: nil, recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextSet)

        harness.model.send(.endWorkout)
        harness.model.onDisappear()

        XCTAssertEqual(recorder.evidence.count, 1)
    }

    func testAFinishedExerciseIsNotRecordedAgainWhenTheScreenCloses() {
        let exercise = twoSets(target: 5)
        let recorder = FakeEvidenceRecorder()
        recorder.setRung(ActiveRung(family: .push, rungDose: RungDose(variant: wall, dose: .reps(5))), for: exercise.id)
        let harness = makeHarness(exercises: [exercise], launch: nil, recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextSet)
        harness.model.send(.start)
        harness.model.send(.nextSet)
        harness.model.rateEffort(.okay)

        harness.model.onDisappear()

        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(recorder.evidence.first?.completion, .completed)
    }

    func testEndingDuringRestBetweenSetsOfARoutineExerciseRecordsIt() throws {
        let exercise = twoSets(target: 5)
        let recorder = FakeEvidenceRecorder()
        recorder.setRung(ActiveRung(family: .push, rungDose: RungDose(variant: wall, dose: .reps(5))), for: exercise.id)
        let routine = WorkoutPlan(id: UUID(), name: "My routine", items: [
            WorkoutPlanItem(id: TodaySessionFlowTests.uuid(0x41), exerciseID: exercise.id, sets: 2, targetReps: 5...5)
        ])
        let harness = makeHarness(exercises: [exercise], launch: nil, plan: routine, recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextSet)

        harness.model.send(.endWorkout)
        harness.model.onDisappear()

        XCTAssertEqual(recorder.evidence.count, 1)
        XCTAssertEqual(recorder.evidence.first?.completion, .endedWorkout)
        XCTAssertEqual(recorder.evidence.first?.setAmounts, [.reps(5)])
    }

    func testUnfinishedWorkInAnInactiveFamilyIsNotRecorded() {
        let exercise = twoSets(target: 5)
        let recorder = FakeEvidenceRecorder()
        let harness = makeHarness(exercises: [exercise], launch: nil, recorder: recorder)
        open(harness)
        harness.model.send(.start)
        harness.model.send(.nextSet)

        harness.model.send(.endWorkout)
        harness.model.onDisappear()

        XCTAssertTrue(recorder.evidence.isEmpty)
    }

    // MARK: - Saved names (review finding 4)

    func testSavedEntriesAreNamedFromTheirPlanOccurrence() throws {
        let plan = WorkoutPlan(id: AdaptiveTrainingCoordinator.todaySessionPlanID, name: "Today's Session", items: [
            WorkoutPlanItem(id: mainID, exerciseID: .wallPushUp, sets: 1, targetReps: 3...3, reducedRange: true),
            WorkoutPlanItem(id: sampleID, exerciseID: .wallPushUp, sets: 1, targetReps: 1...1, isOptional: true)
        ])
        var session = WorkoutSession(exercises: ExerciseCatalog.all, initialExercise: .wallPushUp, plan: plan)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.command(.start), at: 1)
        _ = session.handle(.command(.nextSet), at: 2)
        _ = session.handle(.command(.nextExercise), at: 3)

        let record = try XCTUnwrap(WorkoutRecord(session: session, startedAt: Date(timeIntervalSince1970: 0),
                                                 endedAt: Date(timeIntervalSince1970: 30)))

        XCTAssertEqual(record.entries.map(\.name), ["Shallow Wall Push-Up", "Optional: Wall Push-Up"])
        XCTAssertEqual(record.entries.map(\.outcome), [.completed, .skipped])
        let rows = WorkoutCompletionStats(record: record).exerciseRows
        XCTAssertEqual(rows.map(\.name), ["Shallow Wall Push-Up", "Optional: Wall Push-Up"],
                       "The stats don't add a second prefix to a name that has one.")
        XCTAssertEqual(rows.last?.summary, "Optional: Wall Push-Up — Optional, skipped")
    }

    func testOrdinaryPlanEntriesKeepTheirExerciseNames() throws {
        let plan = WorkoutPlan(id: UUID(), name: "Routine", items: [
            WorkoutPlanItem(id: UUID(), exerciseID: .wallPushUp, sets: 1, targetReps: 3...3)
        ])
        var session = WorkoutSession(exercises: ExerciseCatalog.all, initialExercise: .wallPushUp, plan: plan)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.command(.start), at: 1)
        _ = session.handle(.command(.nextSet), at: 2)

        let record = try XCTUnwrap(WorkoutRecord(session: session, startedAt: Date(timeIntervalSince1970: 0),
                                                 endedAt: Date(timeIntervalSince1970: 30)))

        XCTAssertEqual(record.entries.map(\.name), ["Wall Push-Up"])
    }

    // MARK: - Replaying plan variants (review finding 5)

    func testARecordingOfAShallowMainAndFullSampleReplaysEachVariant() throws {
        let wallPushUp = WallPushUpExercise.definition()
        let shallow = try XCTUnwrap(wallPushUp.reducedRange?())
        let store = MemoryWorkoutRecordingStore()
        let recorder = WorkoutSessionRecorder(store: store)
        let plan = WorkoutPlan(id: AdaptiveTrainingCoordinator.todaySessionPlanID, name: "Today's Session", items: [
            WorkoutPlanItem(id: mainID, exerciseID: .wallPushUp, sets: 1, targetReps: 1...1, reducedRange: true),
            WorkoutPlanItem(id: sampleID, exerciseID: .wallPushUp, sets: 1, targetReps: 1...1, isOptional: true)
        ])
        let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), exercises: [wallPushUp],
                                               initialExercise: .wallPushUp, recorder: recorder, plan: plan)
        open(harness)
        var time = 0.0
        func frame(_ exercise: ExerciseDefinition) {
            harness.scheduler.advance(by: 0.1)
            time += 0.1
            harness.camera.emit(.frame(ReadyPoseFixtures.demoFrame(exercise, motionTime: time, at: time)))
        }

        for _ in 0..<10 { frame(shallow) }
        if harness.model.session.phase != .exercising { harness.model.send(.start) }
        var steps = 0
        while harness.model.session.phase == .exercising, steps < 400 { frame(shallow); steps += 1 }
        XCTAssertEqual(harness.model.session.phase, .resting, "The shallow main item counted its rep.")

        harness.model.send(.start)
        steps = 0
        while harness.model.session.phase == .exercising, steps < 600 { frame(wallPushUp); steps += 1 }
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete, "The full-range sample counted its rep.")

        let text = "[\n" + store.writer(for: recorder.id).lines.joined(separator: ",\n") + "\n]\n"
        XCTAssertTrue(text.contains(#""reducedRange":true"#), "The plan item records its reduced range.")
        XCTAssertTrue(text.contains(#""optional":true"#), "The plan item records that it is optional.")
        XCTAssertTrue(text.contains(#""wall_push_up.reducedRange":"#), "The header carries the variant's own entry.")
        XCTAssertTrue(text.contains(#""variant":"reducedRange""#), "The main item's exercise control names its variant.")
        let frames = try WorkoutSessionReplayer.replay(WorkoutSessionFile(text: text))
        XCTAssertGreaterThanOrEqual(frames.flatMap(\.recorded.reps).count, 2, "A rep from each variant was recorded.")
        for frame in frames where frame.recorded != frame.replayed {
            XCTFail("line \(frame.line): recorded \(frame.recorded), replayed \(frame.replayed)")
        }
    }

    func testTheNextOccurrenceOfTheSameExerciseKeepsItsFramingSoItCanCount() {
        // A shallow floor then its full-range sample share an exercise id and camera view. The camera reports framing
        // only when it changes, so resetting it between them would leave counting off for the second set.
        let plan = WorkoutPlan(id: nil, name: "Plan", items: [
            WorkoutPlanItem(id: mainID, exerciseID: .wallPushUp, sets: 1, targetReps: 3...3, reducedRange: true),
            WorkoutPlanItem(id: sampleID, exerciseID: .wallPushUp, sets: 1, targetReps: 1...1, isOptional: true)
        ])
        var session = WorkoutSession(exercises: ExerciseCatalog.all, initialExercise: .wallPushUp, plan: plan)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: 1)
        _ = session.handle(.command(.start), at: 2)
        XCTAssertTrue(session.isCounting)

        _ = session.handle(.command(.nextSet), at: 5)
        XCTAssertEqual(session.phase, .resting)
        XCTAssertTrue(session.framing.isReliable, "The same exercise seen the same way keeps its framing.")

        _ = session.handle(.command(.start), at: 6)
        XCTAssertTrue(session.isCounting, "So the second set counts without the camera having to report a change.")
    }

    func testANewExerciseInThePlanIsFramedAfresh() {
        let plan = WorkoutPlan(id: nil, name: "Plan", items: [
            WorkoutPlanItem(id: mainID, exerciseID: .wallPushUp, sets: 1, targetReps: 3...3),
            WorkoutPlanItem(id: sampleID, exerciseID: .inclinePushUp, sets: 1, targetReps: 1...1)
        ])
        var session = WorkoutSession(exercises: ExerciseCatalog.all, initialExercise: .wallPushUp, plan: plan)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: 1)
        _ = session.handle(.command(.start), at: 2)

        _ = session.handle(.command(.nextSet), at: 5)

        XCTAssertFalse(session.framing.isReliable, "A different exercise needs its own framing.")
    }

    func testPlanItemsWithoutModifiersRecordExactlyAsBefore() throws {
        let store = MemoryWorkoutRecordingStore()
        let recorder = WorkoutSessionRecorder(store: store)
        let plan = WorkoutPlan(id: UUID(), name: "Routine", items: [
            WorkoutPlanItem(id: mainID, exerciseID: .wallPushUp, sets: 1, targetReps: 3...3)
        ])
        let harness = WorkoutCoachHarness.make(preferences: InMemoryPreferences(), exercises: [WallPushUpExercise.definition()],
                                               initialExercise: .wallPushUp, recorder: recorder, plan: plan)
        open(harness)

        let text = store.writer(for: recorder.id).lines.joined(separator: "\n")

        XCTAssertTrue(text.contains("\"wall_push_up\":"), "The header still has the exercise.")
        XCTAssertFalse(text.contains("\"reducedRange\":"), "An ordinary plan item adds no modifier keys.")
        XCTAssertFalse(text.contains("\"optional\":"))
        XCTAssertFalse(text.contains("\"variant\":"))
        XCTAssertFalse(text.contains("wall_push_up.reducedRange"))
    }

    // MARK: - Fixtures

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

    /// Today's Session as the coordinator would prepare it: a main item and, optionally, the harder sample.
    private func launch(exercise: ExerciseDefinition, dose: Dose, withSample: Bool = false) -> TodaySessionLaunch {
        var items = [AdaptivePlanItem(itemID: mainID, role: .main, family: .push,
                                      rungDose: RungDose(variant: shallow, dose: dose), exerciseID: exercise.id,
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
            items: items.map { PrescriptionItem(id: $0.itemID, family: $0.family, target: $0.rungDose, role: $0.role) },
            rationale: "Test")
        return TodaySessionLaunch(prescription: prescription,
                                  plan: WorkoutPlan(id: AdaptiveTrainingCoordinator.todaySessionPlanID,
                                                    name: "Today's Session", items: planItems),
                                  items: items)
    }

    private func makeHarness(exercises: [ExerciseDefinition], launch: TodaySessionLaunch?, plan: WorkoutPlan? = nil,
                             recorder: FakeEvidenceRecorder) -> WorkoutCoachHarness {
        WorkoutCoachHarness.make(preferences: InMemoryPreferences(), exercises: exercises,
                                 initialExercise: exercises.first?.id ?? .shoulderPress,
                                 plan: launch?.plan ?? plan, adaptive: recorder, todayLaunch: launch)
    }

    private func open(_ harness: WorkoutCoachHarness) {
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
    }

    /// Frames of the guide's own demonstration at the camera's real cadence, until the one rep counts.
    private func driveOneRep(_ harness: WorkoutCoachHarness, exercise: ExerciseDefinition) {
        driveSet(harness, exercise: exercise) { $0.session.phase != .exercising }
    }

    /// Gets framed and starts the set, then plays the guide's demonstration at the camera's real cadence until `stop`
    /// says so (or 400 frames pass).
    private func driveSet(_ harness: WorkoutCoachHarness, exercise: ExerciseDefinition,
                          until stop: (WorkoutCoachModel) -> Bool) {
        var time = 0.0
        func frame() {
            harness.scheduler.advance(by: 0.1)
            time += 0.1
            harness.camera.emit(.frame(ReadyPoseFixtures.demoFrame(exercise, motionTime: time, at: time)))
        }
        for _ in 0..<10 { frame() }
        if harness.model.session.phase != .exercising { harness.model.send(.start) }
        var steps = 0
        while harness.model.session.phase == .exercising, !stop(harness.model), steps < 400 {
            frame()
            steps += 1
        }
    }

    /// A self-reported exercise with two sets, so the workout can end between them.
    private func twoSets(target: Int) -> ExerciseDefinition {
        var copy = selfReported(target: target)
        copy.sets = 2
        return copy
    }

    private func todayRecord(endedAt: Date, startedAt: TimeInterval = 100) -> WorkoutRecord {
        WorkoutRecord(startedAt: Date(timeIntervalSince1970: startedAt), endedAt: endedAt,
                      planID: AdaptiveTrainingCoordinator.todaySessionPlanID, planName: "Today's Session",
                      entries: [WorkoutRecordEntry(exerciseID: .wallPushUp, name: "Shallow Wall Push-Up",
                                                   outcome: .completed, sets: [RecordedSet(reps: 1)])])
    }
}

/// Records evidence and answers active-rung lookups from a table the test fills in.
@MainActor
private final class FakeEvidenceRecorder: AdaptiveEvidenceRecording {
    private(set) var evidence: [AdaptiveEvidence] = []
    private var rungs: [String: ActiveRung] = [:]

    func setRung(_ rung: ActiveRung, for exerciseID: ExerciseID, reducedRange: Bool = false) {
        rungs[key(exerciseID, reducedRange)] = rung
    }

    func activeRung(for exerciseID: ExerciseID, reducedRange: Bool) -> ActiveRung? {
        rungs[key(exerciseID, reducedRange)]
    }

    func record(_ evidence: AdaptiveEvidence) {
        self.evidence.append(evidence)
    }

    private func key(_ exerciseID: ExerciseID, _ reducedRange: Bool) -> String {
        "\(exerciseID.rawValue)|\(reducedRange)"
    }
}

@MainActor
private final class RecordingHistoryRepository: WorkoutHistoryRepository {
    private(set) var saved: [WorkoutRecord] = []

    func list() throws -> [WorkoutRecord] { saved }
    func save(_ record: WorkoutRecord) throws { saved.append(record) }
    func updateWeights(for record: WorkoutRecord) throws {}
    func delete(id: UUID) throws {}
}
