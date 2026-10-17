import Foundation

/// Builds the on-device services used by a live Workout Coach presentation.
@MainActor
final class WorkoutCoachFactory {
    private let preferences: any AppPreferencesStoring
    private let exerciseCatalog: any ExerciseCatalogProviding
    private let routines: (any RoutineRepository)?

    init(preferences: any AppPreferencesStoring,
         exerciseCatalog: any ExerciseCatalogProviding,
         routines: (any RoutineRepository)?) {
        self.preferences = preferences
        self.exerciseCatalog = exerciseCatalog
        self.routines = routines
    }

    func makeWorkout(exerciseID: ExerciseID?, routineID: UUID?) -> WorkoutCoachModel {
        let plan = routineID.flatMap { id in
            try? routines?.list().first(where: { $0.id == id })?.plan(in: exerciseCatalog.all)
        }
        let audio = WorkoutAudioSession()
        // Sets and reps the user adjusted on the list apply here; Saved Sets bring their own.
        let exercises = ExerciseTargetStore.applying(to: exerciseCatalog.all, preferences: preferences)
        let voice = WorkoutVoiceController(recognizer: OnDeviceSpeechRecognizer(),
                                           parser: VoiceCommandParser(exercises: exercises),
                                           permissions: SystemVoicePermissions(), audio: audio)
        let camera = WorkoutCameraController()
        return WorkoutCoachModel(camera: camera, previewProvider: camera,
                                 permission: SystemCameraPermission(), speech: SpeechCoach(audio: audio),
                                 audio: audio, tiltMonitor: CoreMotionTiltMonitor(), voice: voice,
                                 clock: SystemClock(), scheduler: MainScheduler(), preferences: preferences,
                                 exercises: exercises, initialExercise: exerciseID ?? exercises.first?.id,
                                 plan: plan)
    }
}
