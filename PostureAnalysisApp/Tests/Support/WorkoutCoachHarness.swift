import Foundation
@testable import PostureAnalysisApp

/// A `WorkoutCoachModel` wired to fakes, with a manual clock and scheduler.
@MainActor
struct WorkoutCoachHarness {
    let model: WorkoutCoachModel
    let camera: FakePoseFrameSource
    let permission: FakeCameraPermission
    let speech: FakeSpeechCoach
    let audio: FakeAudioSession
    let tilt: FakeTiltMonitor
    let voice: FakeVoiceController
    let clock: ManualClock
    let scheduler: ManualScheduler

    static func make(permissionStatus: CameraAuthorization = .authorized,
                     preferences: any AppPreferencesStoring = UserDefaultsPreferences(),
                     initialExercise: ExerciseID = .shoulderPress) -> WorkoutCoachHarness {
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
            initialExercise: initialExercise,
            plan: nil
        )
        return WorkoutCoachHarness(model: model, camera: camera, permission: permission, speech: speech,
                                   audio: audio, tilt: tilt, voice: voice, clock: clock, scheduler: scheduler)
    }
}
