import XCTest
@testable import PostureAnalysisApp

@MainActor
final class WorkoutIntentTests: XCTestCase {
    func testStartPauseResumeAndNextSetFollowExistingReducerPaths() {
        let harness = makeHarness()
        harness.model.send(.start)
        XCTAssertEqual(harness.model.session.phase, .exercising)

        harness.model.send(.pause)
        XCTAssertEqual(harness.model.session.phase, .paused(.user))

        harness.model.send(.resume)
        XCTAssertEqual(harness.model.session.phase, .exercising)

        harness.model.send(.nextSet)
        XCTAssertEqual(harness.model.session.phase, .resting)
    }

    func testRestartSetUsesExistingReducerEffect() {
        let harness = makeHarness()
        harness.model.send(.start)
        harness.model.send(.restartSet)

        XCTAssertEqual(harness.model.session.phase, .exercising)
        XCTAssertTrue(harness.speech.utterances.contains { $0.text == "Set restarted. Counting from zero." })
    }

    func testChangeAndChooseExerciseUseExistingReducerPaths() {
        let harness = makeHarness()
        harness.model.send(.changeExercise)
        XCTAssertEqual(harness.model.session.phase, .changingExercise(previous: .framing))

        harness.model.send(.chooseExercise(.hammerCurl))

        XCTAssertEqual(harness.model.session.exerciseID, .hammerCurl)
        XCTAssertEqual(harness.model.session.phase, .framing)
    }

    func testNextExerciseAdvancesTheActiveSavedSet() {
        let first = WorkoutPlanItem(id: UUID(), exerciseID: .shoulderPress, sets: 2, targetReps: 8...10)
        let second = WorkoutPlanItem(id: UUID(), exerciseID: .hammerCurl, sets: 2, targetReps: 10...10)
        let plan = WorkoutPlan(name: "Upper Body", items: [first, second])
        let harness = makeHarness(plan: plan)

        harness.model.send(.nextExercise)

        XCTAssertEqual(harness.model.session.exerciseID, .hammerCurl)
        XCTAssertEqual(harness.model.session.planIndex, 1)
        XCTAssertEqual(harness.model.session.planRecords[first.id]?.outcome, .skipped)
    }

    func testEndWorkoutStopsTheCameraThroughExistingEffect() {
        let harness = makeHarness()
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        harness.model.send(.endWorkout)

        XCTAssertEqual(harness.model.session.phase, .ended)
        XCTAssertGreaterThan(harness.camera.stops, 0)
    }

    func testMuteIntentsPersistInInjectedDefaults() {
        let suiteName = "WorkoutIntentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let harness = makeHarness(preferences: UserDefaultsPreferences(defaults: defaults))

        harness.model.send(.toggleCoachMute)
        harness.model.send(.setMicrophoneMuted(true))

        XCTAssertTrue(harness.model.isCoachMuted)
        XCTAssertTrue(harness.model.isMicMuted)
        XCTAssertTrue(defaults.bool(forKey: "workoutCoach.coachMuted"))
        XCTAssertTrue(defaults.bool(forKey: "workoutCoach.micMuted"))
    }

    func testMicrophoneToggleKeepsTheCurrentStatusAwareTapPath() {
        let listeningName = "WorkoutIntentTests.Listening.\(UUID().uuidString)"
        let listeningDefaults = UserDefaults(suiteName: listeningName)!
        defer { listeningDefaults.removePersistentDomain(forName: listeningName) }
        let listening = makeHarness(preferences: UserDefaultsPreferences(defaults: listeningDefaults))
        listening.voice.status = .listening
        listening.model.send(.toggleMicrophoneMute)
        XCTAssertTrue(listening.model.isMicMuted)
        XCTAssertEqual(listening.voice.mutedValues, [true])

        let pausedName = "WorkoutIntentTests.Paused.\(UUID().uuidString)"
        let pausedDefaults = UserDefaults(suiteName: pausedName)!
        defer { pausedDefaults.removePersistentDomain(forName: pausedName) }
        let paused = makeHarness(preferences: UserDefaultsPreferences(defaults: pausedDefaults))
        paused.model.onAppear(isApplicationActive: true)
        paused.voice.status = .paused
        paused.model.send(.toggleMicrophoneMute)
        XCTAssertFalse(paused.model.isMicMuted)
        XCTAssertEqual(paused.voice.retryCount, 1)
    }

    func testDismissTipIntentClearsTheExistingTipState() {
        let harness = makeHarness()
        harness.model.send(.start)
        XCTAssertNotNil(harness.model.activeTip)

        harness.model.send(.dismissTip)

        XCTAssertNil(harness.model.activeTip)
    }

    func testCameraScreenPresentationAndMeasurementIntentsUseModelMethods() {
        let suiteName = "WorkoutIntentTests.Presentation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let harness = makeHarness(preferences: UserDefaultsPreferences(defaults: defaults))
        harness.model.send(.showGuide)
        XCTAssertTrue(harness.model.isGuidePresented)
        harness.model.send(.hideGuide)
        XCTAssertFalse(harness.model.isGuidePresented)

        harness.model.send(.showVoiceHelp)
        XCTAssertTrue(harness.model.isHelpPresented)
        harness.model.send(.hideVoiceHelp)
        XCTAssertFalse(harness.model.isHelpPresented)

        harness.model.send(.toggleMeasurements)
        XCTAssertTrue(harness.model.showsMeasurements)
    }

    private func makeHarness(preferences: any AppPreferencesStoring = UserDefaultsPreferences(),
                             plan: WorkoutPlan? = nil) -> Harness {
        let clock = ManualClock(now: 10)
        let scheduler = ManualScheduler(clock: clock)
        let camera = FakePoseFrameSource()
        let speech = FakeSpeechCoach()
        let voice = FakeVoiceController()
        let model = WorkoutCoachModel(camera: camera,
                                      previewProvider: nil,
                                      permission: FakeCameraPermission(status: .authorized),
                                      speech: speech,
                                      audio: FakeAudioSession(),
                                      tiltMonitor: FakeTiltMonitor(),
                                      voice: voice,
                                      clock: clock,
                                      scheduler: scheduler,
                                      preferences: preferences,
                                      exercises: ExerciseCatalog.all,
                                      initialExercise: .shoulderPress,
                                      plan: plan)
        return Harness(model: model, camera: camera, speech: speech, voice: voice)
    }

    private struct Harness {
        let model: WorkoutCoachModel
        let camera: FakePoseFrameSource
        let speech: FakeSpeechCoach
        let voice: FakeVoiceController
    }
}
