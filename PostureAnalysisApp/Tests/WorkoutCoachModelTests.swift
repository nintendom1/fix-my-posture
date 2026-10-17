import XCTest
@testable import PostureAnalysisApp

@MainActor
final class WorkoutCoachModelTests: XCTestCase {
    func testConstructionDoesNotStartCameraVoiceAudioOrTiltServices() {
        let harness = makeHarness()

        XCTAssertEqual(harness.camera.starts, 0)
        XCTAssertEqual(harness.voice.enabledCount, 0)
        XCTAssertTrue(harness.audio.calls.isEmpty)
        XCTAssertEqual(harness.tilt.startCount, 0)
    }

    func testAuthorizedPermissionStartsCameraAndDeniedPermissionDoesNot() {
        let authorized = makeHarness(permissionStatus: .authorized)
        authorized.model.onAppear(isApplicationActive: true)
        XCTAssertEqual(authorized.camera.starts, 1)

        let denied = makeHarness(permissionStatus: .denied)
        denied.model.onAppear(isApplicationActive: true)
        XCTAssertEqual(denied.model.cameraStatus, .notAuthorized)
        XCTAssertEqual(denied.camera.starts, 0)
    }

    func testAudioInterruptionPausesActiveSession() {
        let harness = makeHarness()
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        harness.model.send(.start)
        XCTAssertEqual(harness.model.session.phase, .exercising)

        harness.audio.emit(.interruptionBegan)

        XCTAssertEqual(harness.model.session.phase, .paused(.interruption))
    }

    func testSchedulerTickRefreshesNowEveryHalfSecond() {
        let harness = makeHarness()
        harness.model.onAppear(isApplicationActive: true)
        XCTAssertEqual(harness.model.now, 10)

        harness.scheduler.advance(by: 0.5)

        XCTAssertEqual(harness.model.now, 10.5, accuracy: 0.0001)
    }

    func testTipExpiresAfterExistingDurationThroughScheduler() {
        let harness = makeHarness()
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        harness.model.send(.start)
        XCTAssertNotNil(harness.model.activeTip)

        harness.scheduler.advance(by: WorkoutCoachModel.tipDuration - 0.01)
        XCTAssertNotNil(harness.model.activeTip)
        harness.scheduler.advance(by: 0.01)

        XCTAssertNil(harness.model.activeTip)
    }

    func testHeardChipExpiresAfterOneAndAHalfSeconds() {
        let harness = makeHarness()
        harness.voice.emitHeard("pause")
        XCTAssertEqual(harness.model.heardPhrase, "pause")

        harness.scheduler.advance(by: 1.49)
        XCTAssertEqual(harness.model.heardPhrase, "pause")
        harness.scheduler.advance(by: 0.01)

        XCTAssertNil(harness.model.heardPhrase)
    }

    func testMutePreferencesPersistInInjectedDefaultsSuite() {
        let suiteName = "WorkoutCoachModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = makeHarness(preferences: UserDefaultsPreferences(defaults: defaults))
        first.model.setCoachMuted(true)
        first.model.setMicMuted(true)

        let second = makeHarness(preferences: UserDefaultsPreferences(defaults: defaults))
        XCTAssertTrue(second.model.isCoachMuted)
        XCTAssertTrue(second.model.isMicMuted)
        XCTAssertTrue(second.voice.mutedValues.isEmpty, "Construction doesn't operate the voice service.")
        second.model.onAppear(isApplicationActive: true)
        XCTAssertEqual(second.voice.mutedValues, [true])
    }

    func testVoiceCommandReachesReducer() {
        let harness = makeHarness()
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        harness.model.send(.start)
        XCTAssertEqual(harness.model.session.phase, .exercising)

        harness.voice.emit(.pause)

        XCTAssertEqual(harness.model.session.phase, .paused(.user))
    }

    private func makeHarness(permissionStatus: CameraAuthorization = .authorized,
                             preferences: any AppPreferencesStoring = UserDefaultsPreferences()) -> Harness {
        let clock = ManualClock(now: 10)
        let scheduler = ManualScheduler(clock: clock)
        let camera = FakePoseFrameSource()
        let permission = FakeCameraPermission(status: permissionStatus)
        let speech = FakeSpeechCoach()
        let audio = FakeAudioSession()
        let tilt = FakeTiltMonitor()
        let voice = FakeVoiceController()
        let model = WorkoutCoachModel(
            camera: camera,
            previewProvider: nil,
            permission: permission,
            speech: speech,
            audio: audio,
            tiltMonitor: tilt,
            voice: voice,
            clock: clock,
            scheduler: scheduler,
            preferences: preferences,
            exercises: ExerciseCatalog.all,
            initialExercise: .shoulderPress,
            plan: nil
        )
        return Harness(model: model, camera: camera, permission: permission, speech: speech,
                       audio: audio, tilt: tilt, voice: voice, clock: clock, scheduler: scheduler)
    }

    private struct Harness {
        let model: WorkoutCoachModel
        let camera: FakePoseFrameSource
        let permission: FakeCameraPermission
        let speech: FakeSpeechCoach
        let audio: FakeAudioSession
        let tilt: FakeTiltMonitor
        let voice: FakeVoiceController
        let clock: ManualClock
        let scheduler: ManualScheduler
    }
}
