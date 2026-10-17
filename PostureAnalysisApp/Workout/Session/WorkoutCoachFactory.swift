import Foundation

/// Builds the on-device services used by a live Workout Coach presentation.
enum WorkoutCoachFactory {
    @MainActor
    static func live(initialExercise: ExerciseID? = nil, plan: WorkoutPlan? = nil) -> WorkoutCoachModel {
        let audio = WorkoutAudioSession()
        // Sets and reps the user adjusted on the list apply here; Saved Sets bring their own.
        let exercises = ExerciseTargetStore.applying(to: ExerciseCatalog.all)
        let voice = WorkoutVoiceController(recognizer: OnDeviceSpeechRecognizer(),
                                           parser: VoiceCommandParser(exercises: exercises),
                                           permissions: SystemVoicePermissions(), audio: audio)
        let camera = WorkoutCameraController()
        return WorkoutCoachModel(camera: camera, previewProvider: camera,
                                 permission: SystemCameraPermission(), speech: SpeechCoach(audio: audio),
                                 audio: audio, tiltMonitor: CoreMotionTiltMonitor(), voice: voice,
                                 clock: SystemClock(), scheduler: MainScheduler(), defaults: .standard,
                                 exercises: exercises, initialExercise: initialExercise ?? exercises.first?.id,
                                 plan: plan)
    }
}
