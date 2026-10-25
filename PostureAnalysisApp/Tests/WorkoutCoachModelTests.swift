import XCTest
@testable import PostureAnalysisApp

@MainActor
final class WorkoutCoachModelTests: XCTestCase {
    func testConstructionDoesNotStartCameraVoiceAudioOrTiltServices() {
        let harness = WorkoutCoachHarness.make()

        XCTAssertEqual(harness.camera.starts, 0)
        XCTAssertEqual(harness.voice.enabledCount, 0)
        XCTAssertTrue(harness.audio.calls.isEmpty)
        XCTAssertEqual(harness.tilt.startCount, 0)
    }

    func testAuthorizedPermissionStartsCameraAndDeniedPermissionDoesNot() {
        let authorized = WorkoutCoachHarness.make(permissionStatus: .authorized)
        authorized.model.onAppear(isApplicationActive: true)
        XCTAssertEqual(authorized.camera.starts, 1)

        let denied = WorkoutCoachHarness.make(permissionStatus: .denied)
        denied.model.onAppear(isApplicationActive: true)
        XCTAssertEqual(denied.model.cameraStatus, .notAuthorized)
        XCTAssertEqual(denied.camera.starts, 0)
    }

    func testAudioInterruptionPausesActiveSession() {
        let harness = WorkoutCoachHarness.make()
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        harness.model.send(.start)
        XCTAssertEqual(harness.model.session.phase, .exercising)

        harness.audio.emit(.interruptionBegan)

        XCTAssertEqual(harness.model.session.phase, .paused(.interruption))
    }

    func testSchedulerTickRefreshesNowEveryHalfSecond() {
        let harness = WorkoutCoachHarness.make()
        harness.model.onAppear(isApplicationActive: true)
        XCTAssertEqual(harness.model.now, 10)

        harness.scheduler.advance(by: 0.5)

        XCTAssertEqual(harness.model.now, 10.5, accuracy: 0.0001)
    }

    func testTipExpiresAfterExistingDurationThroughScheduler() {
        let harness = WorkoutCoachHarness.make()
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
        let harness = WorkoutCoachHarness.make()
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

        let first = WorkoutCoachHarness.make(preferences: UserDefaultsPreferences(defaults: defaults))
        first.model.setCoachMuted(true)
        first.model.setMicMuted(true)

        let second = WorkoutCoachHarness.make(preferences: UserDefaultsPreferences(defaults: defaults))
        XCTAssertTrue(second.model.isCoachMuted)
        XCTAssertTrue(second.model.isMicMuted)
        XCTAssertTrue(second.voice.mutedValues.isEmpty, "Construction doesn't operate the voice service.")
        second.model.onAppear(isApplicationActive: true)
        XCTAssertEqual(second.voice.mutedValues, [true])
    }

    func testDisabledTiltWarningsNeverSurfaceTiltInWorkoutModel() {
        let preferences = InMemoryPreferences()
        preferences.tiltWarningsEnabled = false
        let harness = WorkoutCoachHarness.make(preferences: preferences)

        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        harness.tilt.latestTilt = PhoneTilt(pitchDegrees: 20)
        harness.scheduler.advance(by: 2)

        XCTAssertFalse(harness.model.isPhoneTilted)
    }

    func testVoiceCommandReachesReducer() {
        let harness = WorkoutCoachHarness.make()
        harness.model.onAppear(isApplicationActive: true)
        harness.camera.emit(.running)
        harness.model.send(.start)
        XCTAssertEqual(harness.model.session.phase, .exercising)

        harness.voice.emit(.pause)

        XCTAssertEqual(harness.model.session.phase, .paused(.user))
    }

}
