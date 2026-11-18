import XCTest
@testable import PostureAnalysisApp

final class CameraViewSessionTests: XCTestCase {
    private let reliable = FramingStatus(isReliable: true, guidance: nil)

    func testStanceSwitchesKeepTheSetAndContinueCountingInEitherDirection() {
        for initialStance in [BodyStance.facing, .sideOn] {
            var session = readySession()
            if initialStance == .sideOn {
                _ = session.handle(.stanceObserved(.init(settled: .sideOn, turning: false)), at: 1.5)
            }
            _ = session.handle(.command(.start), at: 2)
            _ = session.handle(.repCompleted(rep(epoch: session.analyzerEpoch)), at: 3)
            let priorProgress = session.progress

            let nextStance: BodyStance = initialStance == .facing ? .sideOn : .facing
            _ = session.handle(.stanceObserved(.init(settled: nextStance, turning: false)), at: 4)

            XCTAssertEqual(session.exercise?.cameraView, nextStance == .sideOn ? .side : .front)
            XCTAssertEqual(session.phase, .exercising)
            XCTAssertTrue(session.isCounting)
            XCTAssertEqual(session.progress, priorProgress)
            XCTAssertEqual(session.repCount, 1)

            _ = session.handle(.repCompleted(rep(epoch: session.analyzerEpoch)), at: 5)
            XCTAssertEqual(session.phase, .exercising)
            XCTAssertEqual(session.repCount, 2)
        }
    }

    func testRepEventsFromAnOldViewEpochAreIgnoredAfterSwitch() {
        var session = readySession()
        _ = session.handle(.command(.start), at: 2)
        let oldEpoch = session.analyzerEpoch
        _ = session.handle(.stanceObserved(.init(settled: .sideOn, turning: false)), at: 3)
        let newEpoch = session.analyzerEpoch

        XCTAssertGreaterThan(newEpoch, oldEpoch)
        _ = session.handle(.repCompleted(rep(epoch: oldEpoch)), at: 4)
        XCTAssertEqual(session.repCount, 0)

        _ = session.handle(.repCompleted(rep(epoch: newEpoch)), at: 5)
        XCTAssertEqual(session.repCount, 1)
    }

    func testViewSwitchEqualizesFrontCountsAndSideRepsCreditBothSides() {
        var session = readySession()
        _ = session.handle(.command(.start), at: 2)
        for time in 3...6 {
            _ = session.handle(.repCompleted(rep(epoch: session.analyzerEpoch)), at: Double(time))
        }
        _ = session.handle(.repCompleted(
            RepEvent(epoch: session.analyzerEpoch, timestamp: 7, sides: [.left])
        ), at: 7)
        XCTAssertEqual(session.sideReps, [.left: 5, .right: 4])
        XCTAssertEqual(session.repCount, 4)

        _ = session.handle(.stanceObserved(.init(settled: .sideOn, turning: false)), at: 8)
        XCTAssertEqual(session.sideReps, [.left: 4, .right: 4])

        // The side-on analyzer follows one near arm and credits the displayed whole-body count on both sides.
        _ = session.handle(.repCompleted(rep(epoch: session.analyzerEpoch)), at: 9)
        XCTAssertEqual(session.repCount, 5)
        _ = session.handle(.repCompleted(rep(epoch: session.analyzerEpoch)), at: 10)
        XCTAssertEqual(session.repCount, 6)
        XCTAssertEqual(session.phase, .exercising)
    }

    func testTurningSuppressesTrackingAndSetupSpeechThenNormalPromptsResume() {
        var session = readySession()
        _ = session.handle(.command(.start), at: 2)
        _ = session.handle(.stanceObserved(.init(settled: .sideOn, turning: true)), at: 3)
        _ = session.handle(.framingChanged(.lost), at: 4)
        XCTAssertTrue(spoken(session.handle(.tick, at: 4.6)).isEmpty)

        _ = session.handle(.stanceObserved(.init(settled: .sideOn, turning: false)), at: 4.7)
        XCTAssertTrue(spoken(session.handle(.tick, at: 5))
            .contains("I can't see you. Step into view, standing side-on to the phone."))

        var framingSession = readySession()
        _ = framingSession.handle(
            .framingChanged(FramingStatus(isReliable: false, guidance: .stepBack)), at: 2
        )
        _ = framingSession.handle(.stanceObserved(.init(settled: nil, turning: true)), at: 2.1)
        XCTAssertTrue(spoken(framingSession.handle(.tick, at: 4)).isEmpty)

        _ = framingSession.handle(.stanceObserved(.init(settled: nil, turning: false)), at: 4.1)
        XCTAssertTrue(spoken(framingSession.handle(.tick, at: 4.2)).contains(FramingGuidance.stepBack.spokenText))
    }

    func testTurningSuppressesFormTipsAndTimedRemindersUntilItClears() {
        var session = readySession()
        _ = session.handle(.command(.start), at: 2)
        _ = session.handle(.stanceObserved(.init(settled: .facing, turning: true)), at: 3)
        let observation = FormObservation(epoch: session.analyzerEpoch, signals: [.curlElbowsIn])

        XCTAssertTrue(session.handle(.formObserved(observation), at: 3.1).isEmpty)
        XCTAssertTrue(session.handle(.formObserved(observation), at: 3.7).isEmpty,
                      "A continuous cue cannot mature while the user is turning.")
        let turningTick = session.handle(.tick, at: 30)
        XCTAssertFalse(turningTick.contains { if case .showTip = $0 { true } else { false } },
                       "A timed reminder waits for the turn to end.")

        _ = session.handle(.stanceObserved(.init(settled: .facing, turning: false)), at: 30.1)
        XCTAssertTrue(session.handle(.formObserved(observation), at: 30.2).isEmpty)
        let cueEffects = session.handle(.formObserved(observation), at: 30.7)
        XCTAssertEqual(cueEffects.compactMap { effect -> CoachingTip? in
            guard case .showTip(let tip) = effect else { return nil }
            return tip
        }.map(\.cue.id), [.curlElbowsIn])
        XCTAssertTrue(spoken(cueEffects).contains("Keep your elbows by your sides."))
    }

    func testManualViewLockKeepsRepsBumpsEpochPersistsAndConfirms() {
        var session = readySession()
        _ = session.handle(.command(.start), at: 2)
        _ = session.handle(.repCompleted(rep(epoch: session.analyzerEpoch)), at: 3)
        let oldEpoch = session.analyzerEpoch
        let priorProgress = session.progress
        let preference = ExerciseViewPreference.locked(.sideOn)

        let effects = session.handle(.command(.setCameraView(preference)), at: 4)

        XCTAssertGreaterThan(session.analyzerEpoch, oldEpoch)
        XCTAssertEqual(session.exercise?.cameraView, .side)
        XCTAssertEqual(session.phase, .exercising)
        XCTAssertTrue(session.isCounting)
        XCTAssertEqual(session.repCount, 1)
        XCTAssertEqual(session.progress, priorProgress)
        XCTAssertTrue(effects.contains(.rememberViewPreference(.hammerCurl, preference)))
        XCTAssertTrue(spoken(effects).contains("Side-on view, locked."))
        XCTAssertEqual(WorkoutIntent.setCameraView(preference).command, .setCameraView(preference))
    }

    func testLockedViewIgnoresStanceChanges() {
        var session = readySession(settings: WorkoutSettings(
            viewPreferences: [.hammerCurl: .locked(.sideOn)]
        ))

        _ = session.handle(.stanceObserved(.init(settled: .facing, turning: true)), at: 2)

        XCTAssertEqual(session.settledStance, .facing)
        XCTAssertFalse(session.isTurning)
        XCTAssertEqual(session.exercise?.cameraView, .side)
        XCTAssertEqual(session.cameraViewTag, "Side-on, locked")
    }

    func testViewSwitchIsAnnouncedAtReadyAndSilentDuringRest() {
        var session = readySession()

        let readyEffects = session.handle(.stanceObserved(.init(settled: .sideOn, turning: false)), at: 2)
        XCTAssertTrue(spoken(readyEffects).contains("Side-on view."))

        _ = session.handle(.command(.start), at: 3)
        _ = session.handle(.command(.nextSet), at: 4)
        XCTAssertEqual(session.phase, .resting)
        let restEffects = session.handle(.stanceObserved(.init(settled: .facing, turning: false)), at: 5)
        XCTAssertEqual(session.exercise?.cameraView, .front)
        XCTAssertFalse(spoken(restEffects).contains("Front view."))
    }

    func testSingleViewExerciseIgnoresCameraCommandsAndClearsSessionStance() {
        let exercise = CameraViewTestFixture.hammerCurl()
        let singleView = ShoulderPressExercise.definition()
        var session = WorkoutSession(
            exercises: [exercise, singleView], initialExercise: exercise.id
        )
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.framingChanged(reliable), at: 1)
        _ = session.handle(.stanceObserved(.init(settled: .sideOn, turning: false)), at: 2)
        XCTAssertEqual(session.settledStance, .sideOn)

        _ = session.handle(.command(.selectExercise(singleView.id)), at: 3)
        XCTAssertNil(session.settledStance)
        XCTAssertNil(session.cameraViewTag)
        let epoch = session.analyzerEpoch
        let effects = session.handle(.command(.setCameraView(.locked(.sideOn))), at: 4)
        XCTAssertTrue(spoken(effects).contains("Dumbbell Shoulder Press has one camera view."))
        XCTAssertEqual(session.analyzerEpoch, epoch)
        XCTAssertEqual(session.viewPreference(for: singleView.id), .auto)

        _ = session.handle(.stanceObserved(.init(settled: .sideOn, turning: true)), at: 5)
        XCTAssertNil(session.settledStance)
        XCTAssertFalse(session.isTurning)
        XCTAssertEqual(session.exercise?.cameraView, singleView.usualView)
    }

    func testCameraViewTagReflectsAutomaticAndLockedViews() {
        var session = readySession()
        XCTAssertNil(session.cameraViewTag)

        _ = session.handle(.stanceObserved(.init(settled: .sideOn, turning: false)), at: 2)
        XCTAssertEqual(session.cameraViewTag, "Side-on")

        let frontLockEffects = session.handle(.command(.setCameraView(.locked(.facing))), at: 3)
        XCTAssertEqual(session.cameraViewTag, "Front, locked")
        XCTAssertTrue(spoken(frontLockEffects).contains("Front view, locked."))
        let sideLockEffects = session.handle(.command(.setCameraView(.locked(.sideOn))), at: 4)
        XCTAssertEqual(session.cameraViewTag, "Side-on, locked")
        XCTAssertTrue(spoken(sideLockEffects).contains("Side-on view, locked."))

        _ = session.handle(.stanceObserved(.init(settled: .facing, turning: false)), at: 5)
        XCTAssertEqual(session.cameraViewTag, "Side-on, locked")
        let autoEffects = session.handle(.command(.setCameraView(.auto)), at: 6)
        XCTAssertNil(session.cameraViewTag)
        XCTAssertTrue(spoken(autoEffects).contains("Auto view, front for now."))
    }

    private func readySession(settings: WorkoutSettings = WorkoutSettings()) -> WorkoutSession {
        let exercise = CameraViewTestFixture.hammerCurl()
        var session = WorkoutSession(exercises: [exercise], initialExercise: exercise.id, settings: settings)
        _ = session.handle(.opened, at: 0)
        _ = session.handle(.framingChanged(reliable), at: 1)
        XCTAssertEqual(session.phase, .ready)
        return session
    }

    private func rep(epoch: Int) -> RepEvent {
        RepEvent(epoch: epoch, timestamp: 0, sides: [.left, .right])
    }

    private func spoken(_ effects: [WorkoutEffect]) -> [String] {
        effects.compactMap { effect in
            guard case .speak(let utterance) = effect else { return nil }
            return utterance.text
        }
    }
}

/// Shared synthetic view-choice definition for reducer, factory, and preference tests.
enum CameraViewTestFixture {
    static func hammerCurl(cameraView: ExerciseCameraView = .front) -> ExerciseDefinition {
        let base = HammerCurlExercise.definition()
        return ExerciseDefinition(
            id: base.id,
            displayName: base.displayName,
            presentation: base.presentation,
            spokenName: base.spokenName,
            sets: base.sets,
            targetReps: base.targetReps,
            autoCompleteReps: base.autoCompleteReps,
            targetRangeAnnouncementReps: base.targetRangeAnnouncementReps,
            restSeconds: base.restSeconds,
            requiredJoints: base.requiredJoints,
            focusSegments: base.focusSegments,
            headroomArmLengths: base.headroomArmLengths,
            sideroomArmLengths: base.sideroomArmLengths,
            maximumShoulderSpan: base.maximumShoulderSpan,
            maximumWristHeightFraction: base.maximumWristHeightFraction,
            supportedShoulders: base.supportedShoulders,
            framingUnreliableAfter: base.framingUnreliableAfter,
            centersInFrame: base.centersInFrame,
            countsArmsIndependently: base.countsArmsIndependently,
            setupLine: base.setupLine,
            voiceAliases: base.voiceAliases,
            guide: base.guide,
            coachingCues: base.coachingCues,
            reminders: base.reminders,
            motionEnvelope: base.motionEnvelope,
            cameraView: cameraView,
            anyOfRequiredJoints: base.anyOfRequiredJoints,
            startsByHolding: base.startsByHolding,
            perSide: base.perSide,
            sideLimb: base.sideLimb,
            warnsAboutTilt: base.warnsAboutTilt,
            equipment: base.equipment,
            plantedJoints: base.plantedJoints,
            tracking: base.tracking,
            doseUnit: base.doseUnit,
            makeAnalyzer: { epoch in
                if cameraView == .side { return HammerCurlSideAnalyzer(epoch: epoch) }
                return base.makeAnalyzer(epoch)
            },
            diagnostics: base.diagnostics,
            reducedRange: base.reducedRange,
            views: [.front, .side],
            buildView: { requestedView in hammerCurl(cameraView: requestedView) }
        )
    }
}

struct CameraViewTestCatalog: ExerciseCatalogProviding {
    let all: [ExerciseDefinition]

    func exercise(_ id: ExerciseID) -> ExerciseDefinition? {
        all.first { $0.id == id }
    }
}
