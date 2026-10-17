import XCTest
@testable import PostureAnalysisApp

final class WorkoutHUDPresenterTests: XCTestCase {
    private let press = ShoulderPressExercise.definition()

    func testStatusTextAndToneForEachPhase() {
        let framing = session(exercise: press) { value in
            _ = value.handle(.framingChanged(FramingStatus(isReliable: false, guidance: .moreHeadroom)), at: 1)
        }
        let ready = readySession()
        let exercising = exercisingSession()
        let notCounting = exercisingSession { value in
            _ = value.handle(.framingChanged(FramingStatus(isReliable: false, guidance: .stepBack)), at: 3)
        }
        let paused = exercisingSession { value in _ = value.handle(.command(.pause), at: 3) }
        let resting = exercisingSession { value in _ = value.handle(.command(.nextSet), at: 3) }
        let complete = completedSession()
        let ended = exercisingSession { value in _ = value.handle(.command(.endWorkout), at: 3) }
        let curl = HammerCurlExercise.definition()
        var changingSession = WorkoutSession(exercises: [press, curl], initialExercise: press.id)
        _ = changingSession.handle(.opened, at: 0)
        _ = changingSession.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: 1)
        _ = changingSession.handle(.command(.changeExercise), at: 2)

        let cases: [(String, WorkoutHUDInputs, String, WorkoutHUDStatusTone)] = [
            ("choosing", makeInputs(session(exercise: nil), now: 1), "Choose an exercise", .subdued),
            ("changing", makeInputs(changingSession, now: 2), "Choose an exercise", .subdued),
            ("framing guidance", makeInputs(framing, now: 2), "Step back: leave room overhead", .attention),
            ("ready hold", makeInputs(ready, now: 2), "Hold the dumbbells just above your shoulders to begin", .endPosition),
            ("ready voice hint", makeInputs(ready, now: 4, voiceCommandsAvailable: true), "Say “what can I say” for commands", .endPosition),
            ("exercising", makeInputs(exercising, now: 3), "Counting", .tracked),
            ("exercising not counting", makeInputs(notCounting, now: 3), "Step back: show both arms", .attention),
            ("paused", makeInputs(paused, now: 3), "Paused", .subdued),
            ("resting", makeInputs(resting, now: 4), "Resting", .subdued),
            ("complete", makeInputs(complete, now: 5), "Exercise complete", .subdued),
            ("ended", makeInputs(ended, now: 4), "Workout ended", .subdued)
        ]

        for (name, input, text, tone) in cases {
            let presentation = WorkoutHUDPresenter.derive(input)
            XCTAssertEqual(presentation.statusText, text, name)
            XCTAssertEqual(presentation.statusTone, tone, name)
        }
    }

    func testReadyStatusPreservesVoiceAndNonHoldingPrompts() {
        var noHold = press
        noHold.startsByHolding = false
        let source = readySession(exercise: noHold)

        XCTAssertEqual(WorkoutHUDPresenter.derive(makeInputs(source, now: 2)).statusText, "Tap Start to begin")
        XCTAssertEqual(WorkoutHUDPresenter.derive(makeInputs(source, now: 2, voiceCommandsAvailable: true)).statusText,
                       "Say “start” to begin")
        XCTAssertEqual(WorkoutHUDPresenter.derive(makeInputs(session(exercise: nil), now: 1)).statusText, "Choose an exercise")

        let readyWithoutExercise = WorkoutHUDInputs(
            visual: WorkoutVisualInputs(phase: .ready, isCounting: false, framing: .lost,
                                        restRemaining: nil, isPhoneTilted: false, activeTip: nil,
                                        hasPose: false, now: 1, lastRepAt: nil),
            exercise: nil,
            voiceCommandsAvailable: false,
            currentSetNumber: 1,
            currentSide: nil,
            repCount: 0,
            repEventCount: 0,
            isRestingBeforeNextExercise: false,
            planPositionLabel: nil
        )
        XCTAssertEqual(WorkoutHUDPresenter.derive(readyWithoutExercise).statusText, "Ready")
    }

    func testPrimaryButtonPerPhase() {
        let ready = readySession()
        let exercising = exercisingSession()
        let paused = exercisingSession { value in _ = value.handle(.command(.pause), at: 3) }
        let resting = exercisingSession { value in _ = value.handle(.command(.nextSet), at: 3) }
        let curl = HammerCurlExercise.definition()
        var changing = WorkoutSession(exercises: [press, curl], initialExercise: press.id)
        _ = changing.handle(.opened, at: 0)
        _ = changing.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: 1)
        _ = changing.handle(.command(.changeExercise), at: 2)
        let complete = completedSession()
        let ended = exercisingSession { value in _ = value.handle(.command(.endWorkout), at: 3) }

        let cases: [(WorkoutSession, WorkoutHUDPrimaryButtonKind, String)] = [
            (session(exercise: nil), .disabled, "Start"),
            (changing, .disabled, "Start"),
            (readySession(unframed: true), .start, "Start"),
            (ready, .start, "Start"),
            (exercising, .pause, "Pause"),
            (paused, .resume, "Resume"),
            (resting, .startSet, "Start set 2"),
            (complete, .disabled, "Start"),
            (ended, .disabled, "Start")
        ]

        for (source, kind, label) in cases {
            let button = WorkoutHUDPresenter.derive(makeInputs(source, now: 4)).primaryButton
            XCTAssertEqual(button.kind, kind)
            XCTAssertEqual(button.label, label)
        }
    }

    func testSetLabelPlainPerArmAndSavedSetRound() {
        let plain = readySession()
        XCTAssertEqual(WorkoutHUDPresenter.derive(makeInputs(plain, now: 2)).setLabel, "Set 1 of 2")

        var oneArm = press
        oneArm.perSide = true
        let left = readySession(exercise: oneArm)
        XCTAssertEqual(WorkoutHUDPresenter.derive(makeInputs(left, now: 2)).setLabel, "Set 1 of 2 · Left arm")

        var right = left
        _ = right.handle(.command(.start), at: 2)
        _ = right.handle(.command(.nextSet), at: 3)
        XCTAssertEqual(WorkoutHUDPresenter.derive(makeInputs(right, now: 4)).setLabel, "Set 1 of 2 · Right arm")

        let planned = planSession()
        let presentation = WorkoutHUDPresenter.derive(makeInputs(planned, now: 2))
        XCTAssertEqual(presentation.setLabel, "Set 1 of 3")
        XCTAssertEqual(presentation.planProgressLabel, "Exercise 1 of 2")
    }

    func testSavedSetRestShowsTheUpNextExerciseLine() {
        let session = savedSetRestSession()
        let presentation = WorkoutHUDPresenter.derive(makeInputs(session, now: 4))

        XCTAssertEqual(presentation.setLabel, "Next: set 1 of 1")
        XCTAssertEqual(presentation.planProgressLabel, "Up next: Hammer Curl · 1 set × 10 reps")
    }

    func testProgressLineForExercisePauseRestAndSavedSet() {
        let exercising = exercisingSession()
        let paused = exercisingSession { value in _ = value.handle(.command(.pause), at: 3) }
        let resting = exercisingSession { value in _ = value.handle(.command(.nextSet), at: 3) }
        let plan = planSession()

        XCTAssertEqual(WorkoutHUDPresenter.derive(makeInputs(exercising, now: 3)).progressLine, "Set 1 of 2 · 0 reps")
        XCTAssertEqual(WorkoutHUDPresenter.derive(makeInputs(paused, now: 3)).progressLine, "Set 1 of 2 · 0 reps")
        let restInput = makeInputs(resting, now: 4)
        XCTAssertEqual(WorkoutHUDPresenter.derive(restInput).progressLine,
                       "Resting · \(WorkoutHUDPresenter.format(resting.restRemaining(at: 4)!))")
        XCTAssertEqual(WorkoutHUDPresenter.derive(makeInputs(plan, now: 2)).planProgressLabel, "Exercise 1 of 2")
        var activePlan = plan
        _ = activePlan.handle(.command(.start), at: 2)
        XCTAssertEqual(WorkoutHUDPresenter.derive(makeInputs(activePlan, now: 2)).progressLine, "Set 1 of 3 · 0 reps")
    }

    func testPresentationCarriesRepEventCountAndProgressVisibility() {
        var source = exercisingSession()
        _ = source.handle(.repCompleted(RepEvent(epoch: source.analyzerEpoch, timestamp: 3, sides: [.left, .right])), at: 3)
        let input = makeInputs(source, now: 3)
        let presentation = WorkoutHUDPresenter.derive(input)
        XCTAssertEqual(source.repEventCount, 1)
        XCTAssertEqual(presentation.repEventCount, 1)
        XCTAssertTrue(presentation.showsRepProgress)

        let noExercise = WorkoutHUDPresenter.derive(makeInputs(session(exercise: nil), now: 0))
        XCTAssertFalse(noExercise.showsRepProgress)
        XCTAssertNil(noExercise.setLabel)
    }

    func testCameraPresentationAddsStatePillCountdownActionsAndPlanCopy() {
        let ready = WorkoutHUDPresenter.derive(makeInputs(readySession(), now: 2))
        XCTAssertEqual(ready.pillLabel, "Get in position")
        XCTAssertEqual(ready.pillIcon, "accessibility_new")
        XCTAssertEqual(ready.instructionText, "Hold the dumbbells just above your shoulders")
        XCTAssertEqual(ready.primaryAction, .start)
        XCTAssertEqual(ready.primaryActionLabel, "Start set")
        XCTAssertEqual(ready.primaryActionIcon, "play_arrow")
        XCTAssertEqual(ready.setSummary, "Set 1 of 2 · target 8–10")
        XCTAssertEqual(ready.nextLine, "Next: set 2 of 2 · 8–10 reps")
        XCTAssertEqual(ready.counterTargetText, "/ 10")

        let active = WorkoutHUDPresenter.derive(makeInputs(exercisingSession(), now: 3))
        XCTAssertEqual(active.pillLabel, "Counting")
        XCTAssertEqual(active.pillIcon, "graphic_eq")
        XCTAssertEqual(active.primaryAction, .pause)
        XCTAssertEqual(active.primaryActionLabel, "Pause")

        let pausedSession = exercisingSession { _ = $0.handle(.command(.pause), at: 3) }
        let paused = WorkoutHUDPresenter.derive(makeInputs(pausedSession, now: 3))
        XCTAssertEqual(paused.pillLabel, "Paused")
        XCTAssertEqual(paused.pillIcon, "pause_circle")
        XCTAssertEqual(paused.instructionText, "Say “resume” or tap play")
        XCTAssertEqual(paused.primaryAction, .resume)
        XCTAssertEqual(paused.primaryActionLabel, "Resume")

        let tipInput = makeInputs(exercisingSession(), now: 3,
                                  activeTip: WorkoutVisualTip(id: 1, kind: .corrective, text: "Press all the way up."))
        let tip = WorkoutHUDPresenter.derive(tipInput)
        XCTAssertEqual(tip.pillLabel, "Form tip")
        XCTAssertEqual(tip.pillIcon, "tips_and_updates")
        XCTAssertEqual(tip.instructionText, "Press all the way up.")
        XCTAssertEqual(tip.primaryAction, .pause)

        let restingSession = exercisingSession { _ = $0.handle(.command(.nextSet), at: 3) }
        let resting = WorkoutHUDPresenter.derive(makeInputs(restingSession, now: 35))
        XCTAssertEqual(resting.pillLabel, "Resting")
        XCTAssertEqual(resting.pillIcon, "self_improvement")
        XCTAssertEqual(resting.restCountdownText, "0:58")
        XCTAssertEqual(resting.primaryAction, .nextSet)
        XCTAssertEqual(resting.primaryActionLabel, "Skip rest")
        XCTAssertEqual(resting.primaryActionIcon, "skip_next")
        XCTAssertEqual(resting.nextLine, "Next: set 2 of 2 · 8–10 reps")

        let lost = WorkoutHUDPresenter.derive(makeInputs(exercisingSession(), now: 3, hasPose: false))
        XCTAssertEqual(lost.pillLabel, "Tracking lost")
        XCTAssertEqual(lost.pillIcon, "visibility_off")
        XCTAssertEqual(lost.primaryAction, .pause)

        let tilted = WorkoutHUDPresenter.derive(makeInputs(readySession(), now: 2, isPhoneTilted: true))
        XCTAssertEqual(tilted.pillLabel, "Check the phone")
        XCTAssertEqual(tilted.pillIcon, "screen_rotation")
        XCTAssertEqual(tilted.instructionText, "The phone is tilted. Stand it upright.")

        let plan = WorkoutHUDPresenter.derive(makeInputs(fourExercisePlanSession(), now: 2))
        XCTAssertEqual(plan.subtitle, "Upper Body · exercise 1 of 4")
        XCTAssertEqual(plan.nextLine, "Next: Hammer Curl")
        XCTAssertEqual(tilted.primaryAction, .pause)
        XCTAssertEqual(tilted.primaryActionLabel, "Pause")

        var endedSession = exercisingSession()
        _ = endedSession.handle(.command(.endWorkout), at: 4)
        let ended = WorkoutHUDPresenter.derive(makeInputs(endedSession, now: 5))
        XCTAssertEqual(ended.pillLabel, "Complete")
        XCTAssertEqual(ended.pillIcon, "check_circle")
        XCTAssertNil(ended.primaryAction)
    }

    private func session(exercise: ExerciseDefinition? = nil,
                         mutate: (inout WorkoutSession) -> Void = { _ in }) -> WorkoutSession {
        let selected = exercise ?? press
        var result = WorkoutSession(exercises: [press], initialExercise: exercise == nil ? nil : selected.id)
        mutate(&result)
        return result
    }

    private func readySession(exercise: ExerciseDefinition? = nil, unframed: Bool = false) -> WorkoutSession {
        let selected = exercise ?? press
        var result = WorkoutSession(exercises: [selected], initialExercise: selected.id)
        _ = result.handle(.opened, at: 0)
        if !unframed {
            _ = result.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: 1)
        }
        return result
    }

    private func exercisingSession(mutate: (inout WorkoutSession) -> Void = { _ in }) -> WorkoutSession {
        var result = readySession()
        _ = result.handle(.command(.start), at: 2)
        mutate(&result)
        return result
    }

    private func completedSession() -> WorkoutSession {
        var oneSet = press
        oneSet.sets = 1
        var result = WorkoutSession(exercises: [oneSet], initialExercise: oneSet.id)
        _ = result.handle(.opened, at: 0)
        _ = result.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: 1)
        _ = result.handle(.command(.start), at: 2)
        _ = result.handle(.command(.nextSet), at: 3)
        _ = result.handle(.command(.nextSet), at: 4)
        return result
    }

    private func planSession() -> WorkoutSession {
        let curl = HammerCurlExercise.definition()
        let plan = WorkoutPlan(name: "Upper Body", items: [
            WorkoutPlanItem(id: UUID(), exerciseID: press.id, sets: 3, targetReps: 8...10),
            WorkoutPlanItem(id: UUID(), exerciseID: curl.id, sets: 1, targetReps: 10...10)
        ])
        var result = WorkoutSession(exercises: [press, curl], initialExercise: nil, plan: plan)
        _ = result.handle(.opened, at: 0)
        _ = result.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: 1)
        return result
    }

    private func savedSetRestSession() -> WorkoutSession {
        let curl = HammerCurlExercise.definition()
        let plan = WorkoutPlan(name: "Upper Body", items: [
            WorkoutPlanItem(id: UUID(), exerciseID: press.id, sets: 1, targetReps: 8...10),
            WorkoutPlanItem(id: UUID(), exerciseID: curl.id, sets: 1, targetReps: 10...10)
        ])
        var result = WorkoutSession(exercises: [press, curl], initialExercise: nil, plan: plan)
        _ = result.handle(.opened, at: 0)
        _ = result.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: 1)
        _ = result.handle(.command(.start), at: 2)
        _ = result.handle(.command(.nextSet), at: 3)
        return result
    }

    private func makeInputs(_ session: WorkoutSession, now: TimeInterval,
                            voiceCommandsAvailable: Bool = false,
                            activeTip: WorkoutVisualTip? = nil,
                            isPhoneTilted: Bool = false,
                            hasPose: Bool = true) -> WorkoutHUDInputs {
        let visual = WorkoutVisualInputs(
            phase: session.phase,
            isCounting: session.isCounting,
            framing: session.framing,
            restRemaining: session.restRemaining(at: now),
            isPhoneTilted: isPhoneTilted,
            activeTip: activeTip,
            hasPose: hasPose,
            now: now,
            lastRepAt: session.lastRepAt
        )
        return WorkoutHUDInputs(session: session, visual: visual,
                                voiceCommandsAvailable: voiceCommandsAvailable)
    }

    private func fourExercisePlanSession() -> WorkoutSession {
        let exercises = [press, HammerCurlExercise.definition(), TricepsExtensionExercise.definition(), DumbbellRowExercise.definition()]
        let plan = WorkoutPlan(name: "Upper Body", items: exercises.map {
            WorkoutPlanItem(id: UUID(), exerciseID: $0.id, sets: 2, targetReps: $0.targetReps)
        })
        var result = WorkoutSession(exercises: exercises, initialExercise: nil, plan: plan)
        _ = result.handle(.opened, at: 0)
        _ = result.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: 1)
        return result
    }
}
