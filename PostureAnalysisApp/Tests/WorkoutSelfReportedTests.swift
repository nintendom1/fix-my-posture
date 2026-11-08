import Foundation
import XCTest
@testable import PostureAnalysisApp

final class WorkoutSelfReportedTests: XCTestCase {
    func testSelfReportedSetupSkipsFramingAndUsesNoOpAnalyzer() throws {
        let exercise = exercise(tracking: .selfReported, target: 6...8)
        var session = WorkoutSession(exercises: [exercise], initialExercise: exercise.id)

        let effects = session.handle(.opened, at: 0)

        XCTAssertEqual(session.phase, .ready)
        XCTAssertTrue(spoken(effects).joined().contains("Tap Start"))
        XCTAssertFalse(session.isCounting)
        let analyzer = exercise.makeAnalyzer(session.analyzerEpoch)
        XCTAssertTrue(analyzer is SelfReportedAnalyzer)

        let framingEffects = session.handle(
            .framingChanged(FramingStatus(isReliable: false, guidance: .stepBack)),
            at: 1
        )
        XCTAssertEqual(session.phase, .ready)
        XCTAssertTrue(framingEffects.isEmpty)
    }

    func testDoneRecordsTheAdjustedSelfReportedTarget() throws {
        let exercise = exercise(tracking: .selfReported, target: 6...8)
        var session = openedSession(for: exercise)

        let startEffects = session.handle(.command(.start), at: 2)
        XCTAssertEqual(session.phase, .exercising)
        XCTAssertFalse(session.isCounting)
        XCTAssertTrue(spoken(startEffects).contains("Set 1 of 1: 8 reps. Tap Done when you've finished."))

        let doneEffects = session.handle(.command(.nextSet), at: 20)

        XCTAssertEqual(session.phase, .exerciseComplete)
        XCTAssertEqual(session.progress[exercise.id]?.setReps, [8])
        XCTAssertTrue(spoken(doneEffects).contains { $0.contains("Set 1 done, 8 reps.") })
    }

    func testTimedHoldCountdownEndsAtDeadlineAndSpeaksCompletion() {
        let exercise = exercise(tracking: .selfReported, doseUnit: .seconds, target: 12...12)
        var session = openedSession(for: exercise)
        _ = session.handle(.voiceControlChanged(true), at: 1)

        let startEffects = session.handle(.command(.start), at: 2)
        XCTAssertEqual(session.holdEndsAt, 14)
        XCTAssertTrue(spoken(startEffects).contains("Set 1 of 1. Hold for 12 seconds. Go."))

        XCTAssertTrue(spoken(session.handle(.tick, at: 8.99)).isEmpty)
        XCTAssertEqual(spoken(session.handle(.tick, at: 9)), ["5 seconds."])
        XCTAssertTrue(spoken(session.handle(.tick, at: 10)).isEmpty, "The countdown is announced once.")
        XCTAssertEqual(session.phase, .exercising)

        let finishEffects = session.handle(.tick, at: 14)

        XCTAssertEqual(session.phase, .exerciseComplete)
        XCTAssertNil(session.holdEndsAt)
        XCTAssertEqual(session.progress[exercise.id]?.setReps, [12])
        XCTAssertTrue(spoken(finishEffects).contains { $0.contains("Set 1 done, 12 seconds.") })
    }

    func testTimedHoldPauseResumeAndRestartKeepOrResetRemainingSeconds() throws {
        let exercise = exercise(tracking: .selfReported, doseUnit: .seconds, target: 20...20)
        var session = openedSession(for: exercise)
        _ = session.handle(.command(.start), at: 2)

        _ = session.handle(.command(.pause), at: 7)
        XCTAssertEqual(session.phase, .paused(.user))
        XCTAssertNil(session.holdEndsAt)
        XCTAssertEqual(session.holdRemaining(at: 7), 15)

        _ = session.handle(.command(.resume), at: 30)
        XCTAssertEqual(session.holdEndsAt, 45)
        XCTAssertEqual(session.holdRemaining(at: 30), 15)

        _ = session.handle(.command(.restartSet), at: 32)
        XCTAssertEqual(session.holdEndsAt, 52)
        XCTAssertEqual(session.holdRemaining(at: 32), 20)

        _ = session.handle(.command(.pause), at: 35)
        _ = session.handle(.command(.restartSet), at: 40)
        XCTAssertEqual(session.holdRemaining(at: 40), 20, "Restart while paused restores the full target.")

        let resumeEffects = session.handle(.command(.resume), at: 50)
        XCTAssertEqual(session.holdEndsAt, 70)
        XCTAssertEqual(session.holdRemaining(at: 50), 20)
        XCTAssertTrue(spoken(resumeEffects).contains("Resuming. 20 seconds left."))
    }

    func testEndingTimedHoldEarlyRecordsElapsedWholeSeconds() throws {
        let exercise = exercise(tracking: .selfReported, doseUnit: .seconds, target: 12...12)
        var session = openedSession(for: exercise)
        _ = session.handle(.command(.start), at: 2)

        let doneEffects = session.handle(.command(.nextSet), at: 6.25)

        XCTAssertEqual(session.phase, .exerciseComplete)
        XCTAssertEqual(session.progress[exercise.id]?.setReps, [4])
        XCTAssertTrue(spoken(doneEffects).contains { $0.contains("Set 1 done, 4 seconds.") })
    }

    func testSelfReportedHUDShowsDoneAndVisualStateDoesNotShowTrackingLoss() {
        let exercise = exercise(tracking: .selfReported, target: 6...8)
        var session = openedSession(for: exercise)
        _ = session.handle(.command(.start), at: 2)
        let visual = WorkoutVisualInputs(session: session, now: 3, isPhoneTilted: false,
                                         activeTip: nil, hasPose: false)
        let presentation = WorkoutHUDPresenter.derive(
            WorkoutHUDInputs(session: session, visual: visual, voiceCommandsAvailable: false)
        )
        let state = WorkoutVisualState.derive(visual)

        XCTAssertEqual(presentation.primaryAction, .nextSet)
        XCTAssertEqual(presentation.primaryActionLabel, "Done")
        XCTAssertEqual(presentation.statusText, "Your set")
        XCTAssertEqual(state.primary, .active)
        XCTAssertFalse(state.badges.contains(.lost))
        XCTAssertEqual(state.overlay, .none)
    }

    func testTimedHoldHUDShowsCountdownAndRemainingTime() {
        let exercise = exercise(tracking: .selfReported, doseUnit: .seconds, target: 12...12)
        var session = openedSession(for: exercise)
        _ = session.handle(.command(.start), at: 2)
        let visual = WorkoutVisualInputs(session: session, now: 8, isPhoneTilted: false,
                                         activeTip: nil, hasPose: false)
        let presentation = WorkoutHUDPresenter.derive(
            WorkoutHUDInputs(session: session, visual: visual, voiceCommandsAvailable: false)
        )

        XCTAssertEqual(presentation.counterText, "0:06")
        XCTAssertEqual(presentation.progressLine, "Set 1 of 1 · 0:06 left")
        XCTAssertEqual(presentation.progressValue, 0.5, accuracy: 0.001)
        XCTAssertEqual(presentation.primaryActionLabel, "Done")
    }

    func testRoutineEditorLabelsTimedTargetsInSeconds() throws {
        let exercise = exercise(tracking: .selfReported, doseUnit: .seconds, target: 12...12)
        let item = RoutineEditorItemState(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            exerciseID: exercise.id,
            name: exercise.displayName,
            gradient: exercise.presentation.gradient,
            symbolName: exercise.presentation.symbolName,
            isAvailable: true,
            isPerSide: false,
            setCount: 2,
            minimumReps: 12,
            maximumReps: 12,
            isExpanded: false,
            isTimed: true
        )

        XCTAssertEqual(item.setsAndRepsLabel, "2 × 12 s")
        XCTAssertEqual(item.targetLabel, "2 × 12 s")
    }

    func testTimedWorkoutRecordStoresSecondsSeparatelyFromReps() throws {
        let exercise = exercise(tracking: .selfReported, doseUnit: .seconds, target: 12...12)
        var session = openedSession(for: exercise)
        _ = session.handle(.command(.start), at: 2)
        _ = session.handle(.command(.nextSet), at: 7)

        let record = try XCTUnwrap(WorkoutRecord(
            session: session,
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 10)
        ))
        let entry = try XCTUnwrap(record.entries.first)
        let set = try XCTUnwrap(entry.sets.first)

        XCTAssertEqual(set.reps, 0)
        XCTAssertEqual(set.seconds, 5)
        XCTAssertEqual(set.amountLabel, "5 s")
        XCTAssertEqual(record.totalReps, 0)

        let stats = WorkoutCompletionStats(record: record)
        let row = try XCTUnwrap(stats.exerciseRows.first)
        XCTAssertEqual(stats.totalReps, 0)
        XCTAssertEqual(row.reps, 0)
        XCTAssertEqual(row.seconds, 5)
        XCTAssertEqual(row.summary, "Dumbbell Shoulder Press — 1 set · 5 s")
    }

    func testRecordedSetWithoutSecondsDecodesAsLegacyRepSet() throws {
        let oldJSON = Data(#"{"reps":8,"side":"L","weight":null}"#.utf8)

        let set = try JSONDecoder().decode(RecordedSet.self, from: oldJSON)

        XCTAssertEqual(set.reps, 8)
        XCTAssertEqual(set.side, "L")
        XCTAssertNil(set.seconds)
        XCTAssertEqual(set.amountLabel, "8 reps")
    }

    func testAmountLabelsUseTheSetDoseUnit() {
        XCTAssertEqual(RecordedSet(reps: 1, side: nil, weight: nil).amountLabel, "1 rep")
        XCTAssertEqual(RecordedSet(reps: 8, side: nil, weight: nil).amountLabel, "8 reps")
        XCTAssertEqual(RecordedSet(reps: 0, side: nil, weight: nil, seconds: 1).amountLabel, "1 s")
        XCTAssertEqual(RecordedSet(reps: 0, side: nil, weight: nil, seconds: 20).amountLabel, "20 s")
    }

    @MainActor
    func testSayingDoneFinishesASelfReportedSetUnlessItClosesHelp() {
        let selfReported = exercise(tracking: .selfReported, target: 6...8)
        let harness = WorkoutCoachHarness.make(exercises: [selfReported], initialExercise: selfReported.id)
        harness.model.onAppear(isApplicationActive: true)
        harness.model.send(.start)
        XCTAssertEqual(harness.model.session.phase, .exercising)

        harness.model.setHelpPresented(true)
        harness.voice.emit(.closeHelp)
        XCTAssertFalse(harness.model.isHelpPresented)
        XCTAssertEqual(harness.model.session.phase, .exercising, "Done closing help must not end the set.")

        harness.voice.emit(.closeHelp)
        XCTAssertEqual(harness.model.session.phase, .exerciseComplete)
        XCTAssertEqual(harness.model.session.progress[selfReported.id]?.setReps, [8])
    }

    @MainActor
    func testSayingDoneDuringACameraSetKeepsCounting() {
        let tracked = exercise(tracking: .camera, target: 6...8)
        let harness = WorkoutCoachHarness.make(exercises: [tracked], initialExercise: tracked.id)
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        harness.model.send(.start)
        XCTAssertEqual(harness.model.session.phase, .exercising)

        harness.voice.emit(.closeHelp)
        XCTAssertEqual(harness.model.session.phase, .exercising)
    }

    func testSelfReportedExercisesDrawNoLiveSkeleton() {
        func visual(_ tracking: ExerciseTracking) -> WorkoutVisualState {
            WorkoutVisualState.derive(WorkoutVisualInputs(
                phase: .exercising, isCounting: true, framing: FramingStatus(isReliable: true, guidance: nil),
                restRemaining: nil, isPhoneTilted: false, activeTip: nil, hasPose: true, now: 5, lastRepAt: nil,
                tracking: tracking))
        }
        XCTAssertFalse(visual(.selfReported).showsLiveSkeleton)
        XCTAssertTrue(visual(.camera).showsLiveSkeleton)
    }

    func testCameraTimedHoldIgnoresRepEventsAndRecordsElapsedSeconds() {
        let hold = exercise(tracking: .camera, doseUnit: .seconds, target: 12...12)
        var session = WorkoutSession(exercises: [hold], initialExercise: hold.id)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: 0.5)
        _ = session.handle(.command(.start), at: 1)
        XCTAssertEqual(session.phase, .exercising)
        XCTAssertTrue(session.isCounting)

        for index in 0..<15 {
            let rep = RepEvent(epoch: session.analyzerEpoch, timestamp: 0, sides: [.left, .right])
            _ = session.handle(.repCompleted(rep), at: 2 + Double(index) * 0.1)
        }
        XCTAssertEqual(session.phase, .exercising, "Rep events must not end a hold measured in seconds.")

        _ = session.handle(.command(.nextSet), at: 5)
        XCTAssertEqual(session.progress[hold.id]?.setReps, [4])
    }

    func testCompletionRowsLabelHoldsInSeconds() {
        let hold = WorkoutCompletionStats.ExerciseRow(id: UUID(), name: "Hold", setCount: 2, reps: 0, seconds: 40,
                                                      weightLabel: nil, outcome: .completed)
        let reps = WorkoutCompletionStats.ExerciseRow(id: UUID(), name: "Press", setCount: 1, reps: 1,
                                                      weightLabel: nil, outcome: .completed)
        XCTAssertEqual(hold.amountLabel, "40 s")
        XCTAssertEqual(hold.summary, "Hold — 2 sets · 40 s")
        XCTAssertEqual(reps.amountLabel, "1 rep")
    }

    private func exercise(
        tracking: ExerciseTracking = .selfReported,
        doseUnit: ExerciseDoseUnit = .reps,
        target: ClosedRange<Int> = 6...8
    ) -> ExerciseDefinition {
        var copy = ShoulderPressExercise.definition()
        copy.tracking = tracking
        copy.doseUnit = doseUnit
        copy.targetReps = target
        copy.autoCompleteReps = target.upperBound
        copy.targetRangeAnnouncementReps = nil
        copy.sets = 1
        return copy
    }

    private func openedSession(for exercise: ExerciseDefinition) -> WorkoutSession {
        var session = WorkoutSession(exercises: [exercise], initialExercise: exercise.id)
        _ = session.handle(.opened, at: 0)
        return session
    }

    private func spoken(_ effects: [WorkoutEffect]) -> [String] {
        effects.compactMap { effect in
            if case .speak(let utterance) = effect { return utterance.text }
            return nil
        }
    }
}
