import AdaptiveTraining
import XCTest
@testable import PostureAnalysisApp

final class WorkoutOutcomeAdapterTests: XCTestCase {
    private let evidenceID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 0x01))
    private let workoutID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 0x02))
    private let prescriptionID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 0x03))
    private let itemID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 0x04))
    private let recordedAt = Date(timeIntervalSince1970: 1_000)
    private let shallow = VariantID(rawValue: "push.wall_push_up.shallow")

    // MARK: - Identity and source

    func testTodayItemsAreAdaptiveAndLinkedToTheirPrescriptionItem() {
        let evidence = build(item: item(amounts: [3]), answer: answer(.okay, amount: 3))

        XCTAssertEqual(evidence.id, evidenceID)
        XCTAssertEqual(evidence.recordedAt, recordedAt)
        XCTAssertEqual(evidence.source, .adaptive)
        XCTAssertEqual(evidence.prescriptionID, prescriptionID)
        XCTAssertEqual(evidence.prescriptionItemID, itemID)
        XCTAssertEqual(evidence.workoutID, workoutID)
        XCTAssertEqual(evidence.family, .push)
        XCTAssertEqual(evidence.variant, shallow)
        XCTAssertEqual(evidence.prescribed, .reps(3))
        XCTAssertNil(evidence.calibrationID)
    }

    func testManualItemsHaveNoPrescriptionAndNoPrescribedDose() {
        let evidence = build(identity: manualIdentity, item: item(amounts: [8, 8]), answer: answer(.easy, amount: 8))

        XCTAssertEqual(evidence.source, .manual)
        XCTAssertNil(evidence.prescriptionID)
        XCTAssertNil(evidence.prescriptionItemID)
        XCTAssertNil(evidence.prescribed)
        XCTAssertEqual(evidence.workoutID, workoutID)
        XCTAssertEqual(evidence.variant, shallow)
    }

    func testTheAdapterRecordsNoMidSetTooHardOrBonus() {
        let evidence = build(item: item(amounts: [3]), answer: answer(.tooHard, amount: 3))

        XCTAssertFalse(evidence.midSetTooHard)
        XCTAssertNil(evidence.bonus)
    }

    // MARK: - Camera-counted items

    func testRatingACameraCountUnchangedAcceptsTheTrackerCount() {
        let evidence = build(item: item(amounts: [1], prescribed: 1), answer: answer(.easy, amount: 1))

        XCTAssertEqual(evidence.confirmation, .trackerAccepted)
        XCTAssertEqual(evidence.confirmed, .reps(1))
        XCTAssertEqual(evidence.setAmounts, [.reps(1)])
        XCTAssertEqual(evidence.tracker, TrackerObservation(status: .tracked, observed: .reps(1)))
        XCTAssertEqual(evidence.effort, .easy)
        XCTAssertEqual(evidence.completion, .completed)
    }

    func testChangingTheAmountMakesTheUserTheConfirmationSource() {
        // Revert check (a): recording .trackerAccepted here makes this test fail.
        let evidence = build(item: item(amounts: [3]), answer: answer(.okay, amount: 2, adjusted: true))

        XCTAssertEqual(evidence.confirmation, .user)
        XCTAssertEqual(evidence.confirmed, .reps(2))
        XCTAssertEqual(evidence.setAmounts, [.reps(2)])
        XCTAssertEqual(evidence.tracker, TrackerObservation(status: .tracked, observed: .reps(3)),
                       "What the camera counted stays apart from what the user confirmed.")
    }

    func testChangingTheAmountToZeroIsAConfirmedZeroNotNothing() {
        let evidence = build(item: item(amounts: [3]), answer: answer(.tooHard, amount: 0, adjusted: true))

        XCTAssertEqual(evidence.confirmed, .reps(0))
        XCTAssertEqual(evidence.confirmation, .user)
        XCTAssertEqual(evidence.completion, .stoppedEarly)
    }

    func testAnUnratedUnchangedCameraCountConfirmsNothing() {
        let evidence = build(item: item(amounts: [3]), answer: answer(nil, amount: 3))

        XCTAssertEqual(evidence.confirmation, .none)
        XCTAssertNil(evidence.confirmed)
        XCTAssertTrue(evidence.setAmounts.isEmpty)
        XCTAssertNil(evidence.effort)
        XCTAssertEqual(evidence.tracker.observed, .reps(3))
    }

    func testNoCardAtAllIsTheSameAsUnrated() {
        let evidence = build(item: item(amounts: [3]), answer: nil)

        XCTAssertEqual(evidence.confirmation, .none)
        XCTAssertNil(evidence.confirmed)
        XCTAssertNil(evidence.effort)
    }

    func testTrackingLossWithoutAConfirmationIsNeverCapacityEvidence() {
        let rated = build(item: item(amounts: [2], trackingLost: true), answer: answer(.easy, amount: 2))
        XCTAssertEqual(rated.tracker.status, .lost)
        XCTAssertEqual(rated.tracker.observed, .reps(2))
        XCTAssertEqual(rated.confirmation, .none)
        XCTAssertNil(rated.confirmed, "A rating doesn't vouch for a count the camera lost.")

        let unrated = build(item: item(amounts: [2], trackingLost: true), answer: answer(nil, amount: 2))
        XCTAssertEqual(unrated.tracker.status, .lost)
        XCTAssertEqual(unrated.confirmation, .none)
        XCTAssertNil(unrated.confirmed)
    }

    func testTheUserCanConfirmAnAmountAfterTrackingLoss() {
        let evidence = build(item: item(amounts: [1], trackingLost: true), answer: answer(.okay, amount: 3, adjusted: true))

        XCTAssertEqual(evidence.tracker.status, .lost)
        XCTAssertEqual(evidence.confirmation, .user)
        XCTAssertEqual(evidence.confirmed, .reps(3))
    }

    // MARK: - Self-reported and timed items

    func testSelfReportedItemsAreConfirmedByTheUserAndNeverTracked() {
        let rated = build(item: item(tracking: .selfReported, amounts: [5]), answer: answer(.okay, amount: 5))
        XCTAssertEqual(rated.confirmation, .user)
        XCTAssertEqual(rated.confirmed, .reps(5))
        XCTAssertEqual(rated.tracker, .notTracked)
        XCTAssertNil(rated.tracker.observed)

        let unrated = build(item: item(tracking: .selfReported, amounts: [5]), answer: answer(nil, amount: 5))
        XCTAssertEqual(unrated.confirmation, .user, "The user said the set was done, rated or not.")
        XCTAssertEqual(unrated.confirmed, .reps(5))
    }

    func testTimedHoldsRecordSecondsAndAreNotTracked() {
        let hold = item(unit: .seconds, tracking: .timedHold, amounts: [20], target: 20, prescribed: 20)
        let identity = WorkoutOutcomeAdapter.Identity(
            origin: .adaptive(prescriptionID: prescriptionID, itemID: itemID, prescribed: .seconds(20)),
            family: .core, variant: VariantID(rawValue: "core.abdominal_brace"))
        let evidence = build(identity: identity, item: hold, answer: answer(.easy, amount: 20))

        XCTAssertEqual(evidence.confirmed, .seconds(20))
        XCTAssertEqual(evidence.setAmounts, [.seconds(20)])
        XCTAssertEqual(evidence.confirmation, .user)
        XCTAssertEqual(evidence.tracker, .notTracked)
        XCTAssertEqual(evidence.prescribed, .seconds(20))
        XCTAssertEqual(evidence.completion, .completed)
    }

    func testAnAdjustedHoldIsRecordedInSeconds() {
        let hold = item(unit: .seconds, tracking: .timedHold, amounts: [12], target: 20, prescribed: 20)
        let evidence = build(item: hold, answer: answer(.okay, amount: 15, adjusted: true))

        XCTAssertEqual(evidence.confirmed, .seconds(15))
        XCTAssertEqual(evidence.completion, .stoppedEarly)
    }

    // MARK: - Completion

    func testCompletionBranches() {
        // Every set done at the target.
        XCTAssertEqual(build(item: item(amounts: [3]), answer: answer(.okay, amount: 3)).completion, .completed)
        // Done with less than the target.
        XCTAssertEqual(build(item: item(amounts: [2]), answer: answer(.okay, amount: 2)).completion, .stoppedEarly)
        // The workout ended during the item.
        XCTAssertEqual(build(item: item(amounts: [1], result: .endedWorkout), answer: nil).completion, .endedWorkout)
        // Skipped before any work, such as a declined harder sample.
        XCTAssertEqual(build(item: item(amounts: [], result: .skipped), answer: answer(nil, amount: 0)).completion,
                       .notAttempted)
        // Skipped after some work.
        XCTAssertEqual(build(item: item(amounts: [2], result: .skipped), answer: answer(nil, amount: 2)).completion,
                       .stoppedEarly)
    }

    func testCorrectingTheAmountCorrectsTheCompletionToo() {
        let short = item(amounts: [1], target: 3)
        XCTAssertEqual(build(item: short, answer: answer(.easy, amount: 1)).completion, .stoppedEarly)
        XCTAssertEqual(build(item: short, answer: answer(.easy, amount: 3, adjusted: true)).completion, .completed,
                       "The camera missed reps the user says they did.")
        let full = item(amounts: [3], target: 3)
        XCTAssertEqual(build(item: full, answer: answer(.easy, amount: 2, adjusted: true)).completion, .stoppedEarly)
    }

    func testSkippedItemsConfirmNothingUnlessTheUserSaysTheyDidSome() {
        let skipped = item(amounts: [], result: .skipped)
        let untouched = build(item: skipped, answer: answer(nil, amount: 0))
        XCTAssertEqual(untouched.completion, .notAttempted)
        XCTAssertEqual(untouched.confirmation, .none)
        XCTAssertNil(untouched.confirmed)
        XCTAssertEqual(untouched.tracker, .notTracked, "A camera item skipped before any work never ran.")

        let rated = build(item: skipped, answer: answer(.tooHard, amount: 0))
        XCTAssertEqual(rated.effort, .tooHard, "The rating is kept; the engine decides what a skipped item means.")
        XCTAssertEqual(rated.completion, .notAttempted)
        XCTAssertNil(rated.confirmed)

        let didSome = build(item: skipped, answer: answer(.okay, amount: 1, adjusted: true))
        XCTAssertEqual(didSome.completion, .stoppedEarly)
        XCTAssertEqual(didSome.confirmed, .reps(1))
        XCTAssertEqual(didSome.confirmation, .user)
    }

    func testEndedWorkoutKeepsWhatWasCountedWithoutConfirmingIt() {
        let evidence = build(item: item(amounts: [2], result: .endedWorkout), answer: nil)

        XCTAssertEqual(evidence.completion, .endedWorkout)
        XCTAssertEqual(evidence.tracker, TrackerObservation(status: .tracked, observed: .reps(2)))
        XCTAssertEqual(evidence.confirmation, .none)
        XCTAssertNil(evidence.confirmed)
    }

    func testATooHardRatingOnACompletedItemKeepsBothFacts() {
        let evidence = build(item: item(amounts: [3]), answer: answer(.tooHard, amount: 3))

        XCTAssertEqual(evidence.completion, .completed)
        XCTAssertEqual(evidence.effort, .tooHard)
        XCTAssertEqual(evidence.confirmed, .reps(3))
    }

    // MARK: - Several sets

    func testSeveralSetsKeepEverySetAndConfirmTheSmallest() {
        let evidence = build(identity: manualIdentity, item: item(amounts: [10, 8], target: 8),
                             answer: answer(.okay, amount: 8))

        XCTAssertEqual(evidence.setAmounts, [.reps(10), .reps(8)])
        XCTAssertEqual(evidence.confirmed, .reps(8), "The smallest set, so several sets are never overstated.")
        XCTAssertEqual(evidence.confirmation, .trackerAccepted)
        XCTAssertEqual(evidence.tracker.observed, .reps(8))
    }

    func testAdjustingSeveralSetsAppliesTheAmountToEachSet() {
        let evidence = build(identity: manualIdentity, item: item(amounts: [10, 8], target: 8),
                             answer: answer(.easy, amount: 6, adjusted: true))

        XCTAssertEqual(evidence.setAmounts, [.reps(6), .reps(6)])
        XCTAssertEqual(evidence.confirmed, .reps(6))
        XCTAssertEqual(evidence.confirmation, .user)
    }

    // MARK: - Detecting finished items

    func testACompletedPlanItemIsFoundOnceWithItsSets() throws {
        let exercise = selfReported(target: 3...3)
        let item = WorkoutPlanItem(id: itemID, exerciseID: exercise.id, sets: 1, targetReps: 3...3)
        var session = openedSession(exercise, plan: WorkoutPlan(id: nil, name: "Plan", items: [item]))
        _ = session.handle(.command(.start), at: 1)

        let before = session
        _ = session.handle(.command(.nextSet), at: 5)
        let found = FinishedItemDetector.finishedItems(before: before, after: session, at: 5)

        let finished = try XCTUnwrap(found.first)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(finished.planItemID, itemID)
        XCTAssertEqual(finished.setAmounts, [3])
        XCTAssertEqual(finished.result, .completed)
        XCTAssertEqual(finished.tracking, .selfReported)
        XCTAssertEqual(finished.target, 3)

        let later = session
        _ = session.handle(.tick, at: 6)
        XCTAssertTrue(FinishedItemDetector.finishedItems(before: later, after: session, at: 6).isEmpty,
                      "An item finishes once, not on every later input.")
    }

    func testASkippedPlanItemIsFoundWithNoSets() throws {
        let exercise = selfReported(target: 3...3)
        let items = [WorkoutPlanItem(id: itemID, exerciseID: exercise.id, sets: 1, targetReps: 3...3),
                     WorkoutPlanItem(id: UUID(), exerciseID: exercise.id, sets: 1, targetReps: 3...3, isOptional: true)]
        var session = openedSession(exercise, plan: WorkoutPlan(id: nil, name: "Plan", items: items))
        _ = session.handle(.command(.start), at: 1)

        let before = session
        _ = session.handle(.command(.nextExercise), at: 5)
        let found = FinishedItemDetector.finishedItems(before: before, after: session, at: 5)

        let finished = try XCTUnwrap(found.first)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(finished.planItemID, itemID)
        XCTAssertEqual(finished.result, .skipped)
        XCTAssertTrue(finished.setAmounts.isEmpty)
    }

    func testEndingTheWorkoutDuringATimedItemFindsItEnded() throws {
        var hold = selfReported(target: 20...20)
        hold.doseUnit = .seconds
        let item = WorkoutPlanItem(id: itemID, exerciseID: hold.id, sets: 1, targetReps: 20...20)
        var session = openedSession(hold, plan: WorkoutPlan(id: nil, name: "Plan", items: [item]))
        _ = session.handle(.command(.start), at: 2)

        let before = session
        _ = session.handle(.command(.endWorkout), at: 9)
        let found = FinishedItemDetector.finishedItems(before: before, after: session, at: 9)

        let finished = try XCTUnwrap(found.first)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(finished.result, .endedWorkout)
        XCTAssertEqual(finished.setAmounts, [7])
        XCTAssertEqual(finished.unit, .seconds)
        XCTAssertEqual(finished.tracking, .timedHold)
    }

    func testAStandaloneExerciseFinishesWithItsLastSetOnly() throws {
        var exercise = selfReported(target: 4...4)
        exercise.sets = 2
        var session = openedSession(exercise, plan: nil)

        _ = session.handle(.command(.start), at: 2)
        var before = session
        _ = session.handle(.command(.nextSet), at: 5)
        XCTAssertTrue(FinishedItemDetector.finishedItems(before: before, after: session, at: 5).isEmpty,
                      "The first of two sets doesn't finish the exercise.")

        _ = session.handle(.command(.start), at: 6)
        before = session
        _ = session.handle(.command(.nextSet), at: 9)
        let found = FinishedItemDetector.finishedItems(before: before, after: session, at: 9)
        let finished = try XCTUnwrap(found.first)
        XCTAssertEqual(found.count, 1)
        XCTAssertNil(finished.planItemID)
        XCTAssertEqual(finished.setAmounts, [4, 4])
        XCTAssertEqual(finished.result, .completed)
    }

    func testChoosingAFinishedExerciseDoesNotFinishItAgain() {
        let first = selfReported(target: 3...3)
        let other = ExerciseDefinition.renamed(ShoulderPressExercise.definition(), id: ExerciseID(rawValue: "other_move"))
        var session = WorkoutSession(exercises: [first, other], initialExercise: first.id)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.command(.start), at: 2)
        _ = session.handle(.command(.nextSet), at: 5)

        let before = session
        _ = session.handle(.command(.changeExercise), at: 6)
        _ = session.handle(.command(.selectExercise(other.id)), at: 7)
        _ = session.handle(.command(.changeExercise), at: 8)
        _ = session.handle(.command(.selectExercise(first.id)), at: 9)

        XCTAssertTrue(FinishedItemDetector.finishedItems(before: before, after: session, at: 9).isEmpty)
    }

    // MARK: - Helpers

    private var todayIdentity: WorkoutOutcomeAdapter.Identity {
        .init(origin: .adaptive(prescriptionID: prescriptionID, itemID: itemID, prescribed: .reps(3)),
              family: .push, variant: shallow)
    }

    private var manualIdentity: WorkoutOutcomeAdapter.Identity {
        .init(origin: .manual, family: .push, variant: shallow)
    }

    private func build(identity: WorkoutOutcomeAdapter.Identity? = nil, item: FinishedWorkoutItem,
                       answer: WorkoutOutcomeAdapter.Answer?) -> AdaptiveEvidence {
        WorkoutOutcomeAdapter.evidence(id: evidenceID, recordedAt: recordedAt, workoutID: workoutID,
                                       identity: identity ?? todayIdentity, item: item, answer: answer)
    }

    private func answer(_ effort: EffortFeedback?, amount: Int, adjusted: Bool = false) -> WorkoutOutcomeAdapter.Answer {
        WorkoutOutcomeAdapter.Answer(effort: effort, amount: amount, isAdjusted: adjusted)
    }

    private func item(unit: DoseKind = .reps, tracking: FinishedWorkoutItem.Tracking = .camera, amounts: [Int],
                      target: Int = 3, result: FinishedWorkoutItem.Result = .completed, trackingLost: Bool = false,
                      prescribed: Int? = nil) -> FinishedWorkoutItem {
        FinishedWorkoutItem(planItemID: itemID, exerciseID: .wallPushUp, reducedRange: true, unit: unit,
                            tracking: tracking, setAmounts: amounts, target: prescribed ?? target, result: result,
                            trackingLost: trackingLost)
    }

    private func selfReported(target: ClosedRange<Int>) -> ExerciseDefinition {
        var copy = ShoulderPressExercise.definition()
        copy.tracking = .selfReported
        copy.targetReps = target
        copy.autoCompleteReps = target.upperBound
        copy.targetRangeAnnouncementReps = nil
        copy.sets = 1
        return copy
    }

    /// Opened and ready: a self-reported exercise skips framing, so the set begins on Start.
    private func openedSession(_ exercise: ExerciseDefinition, plan: WorkoutPlan?) -> WorkoutSession {
        var session = WorkoutSession(exercises: [exercise], initialExercise: exercise.id, plan: plan)
        _ = session.handle(.opened, at: 0)
        return session
    }
}

private extension ExerciseDefinition {
    /// The same exercise under another id, so a session can offer two different exercises.
    static func renamed(_ base: ExerciseDefinition, id: ExerciseID) -> ExerciseDefinition {
        ExerciseDefinition(id: id, displayName: base.displayName, presentation: base.presentation,
                           spokenName: base.spokenName, sets: 1, targetReps: base.targetReps,
                           autoCompleteReps: base.autoCompleteReps, targetRangeAnnouncementReps: nil,
                           restSeconds: base.restSeconds, requiredJoints: base.requiredJoints,
                           focusSegments: base.focusSegments, headroomArmLengths: base.headroomArmLengths,
                           countsArmsIndependently: base.countsArmsIndependently, setupLine: base.setupLine,
                           voiceAliases: ["other move"], guide: base.guide, coachingCues: base.coachingCues,
                           reminders: base.reminders, motionEnvelope: base.motionEnvelope,
                           tracking: .selfReported, makeAnalyzer: { SelfReportedAnalyzer(epoch: $0) })
    }
}
