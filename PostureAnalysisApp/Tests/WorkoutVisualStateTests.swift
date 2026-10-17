import XCTest
@testable import PostureAnalysisApp

final class WorkoutVisualStateTests: XCTestCase {
    func testReadyStateIncludesSetupAndSelectionPhases() {
        for phase in [WorkoutPhase.framing, .ready, .choosingExercise, .changingExercise(previous: .ready)] {
            let state = WorkoutVisualState.derive(inputs(phase: phase))
            XCTAssertEqual(state.primary, .ready)
            XCTAssertEqual(state.label, "Get in position")
            XCTAssertEqual(state.iconName, "accessibility_new")
            XCTAssertEqual(state.designRole, .brand)
        }
    }

    func testActiveState() {
        let state = WorkoutVisualState.derive(inputs(phase: .exercising, isCounting: true))
        XCTAssertEqual(state.primary, .active)
        XCTAssertEqual(state.label, "Counting")
        XCTAssertEqual(state.iconName, "graphic_eq")
        XCTAssertEqual(state.designRole, .neutral)
    }

    func testPausedStatePreservesEachPauseReason() {
        for reason in [PauseReason.user, .background, .interruption] {
            let state = WorkoutVisualState.derive(inputs(phase: .paused(reason)))
            XCTAssertEqual(state.primary, .paused(reason))
            XCTAssertEqual(state.label, "Paused")
            XCTAssertEqual(state.iconName, "pause_circle")
            XCTAssertEqual(state.designRole, .warning)
        }
    }

    func testTipStateRequiresAnActiveTipWhileExercising() {
        let tip = WorkoutVisualTip(id: 9, kind: .corrective)
        let state = WorkoutVisualState.derive(inputs(phase: .exercising, isCounting: true, activeTip: tip))
        XCTAssertEqual(state.primary, .tip)
        XCTAssertEqual(state.label, "Form tip")
        XCTAssertEqual(state.iconName, "tips_and_updates")
        XCTAssertEqual(state.designRole, .warning)
        XCTAssertEqual(state.activeTip, tip)
    }

    func testRestStateExposesRemainingTime() {
        let source = inputs(phase: .resting, restRemaining: 12.5)
        let state = WorkoutVisualState.derive(source)
        XCTAssertEqual(state.primary, .rest)
        XCTAssertEqual(state.restRemaining, 12.5)
        XCTAssertEqual(state.label, "Resting")
        XCTAssertEqual(state.iconName, "self_improvement")
        XCTAssertEqual(state.designRole, .rest)
    }

    func testLostStateCoversNotCountingAndMissingPose() {
        for source in [
            inputs(phase: .exercising, isCounting: false),
            inputs(phase: .exercising, isCounting: true, hasPose: false)
        ] {
            let state = WorkoutVisualState.derive(source)
            XCTAssertEqual(state.primary, .lost)
            XCTAssertEqual(state.label, "Tracking lost")
            XCTAssertEqual(state.iconName, "visibility_off")
            XCTAssertEqual(state.designRole, .danger)
        }
    }

    func testTiltState() {
        let state = WorkoutVisualState.derive(inputs(phase: .ready, isPhoneTilted: true))
        XCTAssertEqual(state.primary, .tilt)
        XCTAssertEqual(state.label, "Check the phone")
        XCTAssertEqual(state.iconName, "screen_rotation")
        XCTAssertEqual(state.designRole, .warning)
    }

    func testCompleteStateCoversExerciseAndWorkoutCompletion() {
        for phase in [WorkoutPhase.exerciseComplete, .ended] {
            let state = WorkoutVisualState.derive(inputs(phase: phase))
            XCTAssertEqual(state.primary, .complete)
            XCTAssertEqual(state.label, "Complete")
            XCTAssertEqual(state.iconName, "check_circle")
            XCTAssertEqual(state.designRole, .success)
        }
    }

    func testPrecedenceTableForEveryCoexistingConditionPair() {
        let tip = WorkoutVisualTip(id: 1, kind: .reminder)
        let cases: [(String, WorkoutVisualInputs, WorkoutVisualState.Primary)] = [
            ("paused > tilt", inputs(phase: .paused(.user), isPhoneTilted: true), .paused(.user)),
            ("rest > tilt", inputs(phase: .resting, restRemaining: 4, isPhoneTilted: true), .rest),
            ("tilt > lost", inputs(phase: .exercising, isCounting: false, isPhoneTilted: true), .tilt),
            ("tilt > tip", inputs(phase: .exercising, isCounting: true, isPhoneTilted: true, activeTip: tip), .tilt),
            ("tilt > active", inputs(phase: .exercising, isCounting: true, isPhoneTilted: true), .tilt),
            ("tilt > ready", inputs(phase: .ready, isPhoneTilted: true), .tilt),
            ("lost > tip", inputs(phase: .exercising, isCounting: false, activeTip: tip), .lost),
            ("lost > active", inputs(phase: .exercising, isCounting: true, hasPose: false), .lost),
            ("tip > active", inputs(phase: .exercising, isCounting: true, activeTip: tip), .tip)
        ]

        for (name, source, expected) in cases {
            XCTAssertEqual(WorkoutVisualState.derive(source).primary, expected, name)
        }
    }

    func testLosingConditionsAreListedAsBadges() {
        let state = WorkoutVisualState.derive(inputs(
            phase: .exercising,
            isCounting: false,
            isPhoneTilted: true,
            activeTip: WorkoutVisualTip(id: 1, kind: .corrective),
            hasPose: false
        ))

        XCTAssertEqual(state.primary, .tilt)
        XCTAssertEqual(state.badges, [.tip, .lost])

        let resting = WorkoutVisualState.derive(inputs(phase: .resting, restRemaining: 2, isPhoneTilted: true))
        XCTAssertEqual(resting.primary, .rest)
        XCTAssertEqual(resting.badges, [.tilt])
    }

    func testTipExpiryMeansThereIsNoTipState() {
        let state = WorkoutVisualState.derive(inputs(phase: .exercising, isCounting: true, activeTip: nil))
        XCTAssertEqual(state.primary, .active)
        XCTAssertFalse(state.badges.contains(.tip))
    }

    func testRepFlashWindowDoesNotChangePrimaryState() {
        let before = WorkoutVisualState.derive(inputs(phase: .exercising, isCounting: true, now: 10.69, lastRepAt: 10))
        let after = WorkoutVisualState.derive(inputs(phase: .exercising, isCounting: true, now: 10.71, lastRepAt: 10))

        XCTAssertTrue(before.isRepFlashing)
        XCTAssertFalse(after.isRepFlashing)
        XCTAssertEqual(before.primary, .active)
        XCTAssertEqual(after.primary, .active)
        XCTAssertEqual(WorkoutVisualState.repFlashLabel, "Rep counted")
    }

    private func inputs(
        phase: WorkoutPhase,
        isCounting: Bool = false,
        framing: FramingStatus = .lost,
        restRemaining: TimeInterval? = nil,
        isPhoneTilted: Bool = false,
        activeTip: WorkoutVisualTip? = nil,
        hasPose: Bool = true,
        now: TimeInterval = 20,
        lastRepAt: TimeInterval? = nil
    ) -> WorkoutVisualInputs {
        WorkoutVisualInputs(
            phase: phase,
            isCounting: isCounting,
            framing: framing,
            restRemaining: restRemaining,
            isPhoneTilted: isPhoneTilted,
            activeTip: activeTip,
            hasPose: hasPose,
            now: now,
            lastRepAt: lastRepAt
        )
    }
}
