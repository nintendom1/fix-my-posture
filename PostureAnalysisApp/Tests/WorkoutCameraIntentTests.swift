import XCTest
@testable import PostureAnalysisApp

final class WorkoutCameraIntentTests: XCTestCase {
    func testToolbarAndToggleActionsSendTheirWorkoutIntents() {
        let presentation = readyPresentation()
        let cases: [(WorkoutCameraControl, WorkoutIntent)] = [
            (.exerciseGuide, .showGuide),
            (.restartSet, .restartSet),
            (.nextSet, .nextSet),
            (.skipExercise, .nextExercise),
            (.changeExercise, .changeExercise),
            (.showMeasurements, .toggleMeasurements),
            (.coachMute, .toggleCoachMute),
            (.microphone, .microphoneTapped),
            (.voiceCommands, .showVoiceHelp),
            (.endWorkout, .endWorkout)
        ]

        for (control, expected) in cases {
            XCTAssertEqual(WorkoutCameraControl.intent(for: control, presentation: presentation), expected,
                           "\(control)")
        }
    }

    func testPrimaryButtonUsesPresenterActionAndDisabledStateSendsNothing() {
        let ready = readyPresentation()
        XCTAssertEqual(WorkoutCameraControl.intent(for: .primary, presentation: ready), .start)

        let press = ShoulderPressExercise.definition()
        var session = WorkoutSession(exercises: [press], initialExercise: press.id)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: 1)
        _ = session.handle(.command(.start), at: 2)
        let active = WorkoutHUDPresenter.derive(WorkoutHUDInputs(
            session: session,
            visual: WorkoutVisualInputs(session: session, now: 3, isPhoneTilted: false,
                                        activeTip: nil, hasPose: true),
            voiceCommandsAvailable: true
        ))
        XCTAssertEqual(WorkoutCameraControl.intent(for: .primary, presentation: active), .pause)

        var ended = session
        _ = ended.handle(.command(.endWorkout), at: 3)
        let disabled = WorkoutHUDPresenter.derive(WorkoutHUDInputs(
            session: ended,
            visual: WorkoutVisualInputs(session: ended, now: 4, isPhoneTilted: false,
                                        activeTip: nil, hasPose: false),
            voiceCommandsAvailable: false
        ))
        XCTAssertNil(WorkoutCameraControl.intent(for: .primary, presentation: disabled))
    }

    private func readyPresentation() -> WorkoutHUDPresentation {
        let press = ShoulderPressExercise.definition()
        var session = WorkoutSession(exercises: [press], initialExercise: press.id)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.framingChanged(FramingStatus(isReliable: true, guidance: nil)), at: 1)
        return WorkoutHUDPresenter.derive(WorkoutHUDInputs(
            session: session,
            visual: WorkoutVisualInputs(session: session, now: 2, isPhoneTilted: false,
                                        activeTip: nil, hasPose: true),
            voiceCommandsAvailable: true
        ))
    }
}
