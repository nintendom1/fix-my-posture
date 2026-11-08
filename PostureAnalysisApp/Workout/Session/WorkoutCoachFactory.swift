import Foundation

/// Builds the on-device services used by a live Workout Coach presentation.
@MainActor
final class WorkoutCoachFactory {
    private let preferences: any AppPreferencesStoring
    private let exerciseCatalog: any ExerciseCatalogProviding
    private let routines: (any RoutineRepository)?
    private let recordings: (any WorkoutRecordingStoring)?
    /// Records effort evidence and knows the active rungs; nil when there is no adaptive engine.
    private let adaptive: (any AdaptiveEvidenceRecording)?

    init(preferences: any AppPreferencesStoring,
         exerciseCatalog: any ExerciseCatalogProviding,
         routines: (any RoutineRepository)?,
         recordings: (any WorkoutRecordingStoring)? = nil,
         adaptive: (any AdaptiveEvidenceRecording)? = nil) {
        self.preferences = preferences
        self.exerciseCatalog = exerciseCatalog
        self.routines = routines
        self.recordings = recordings
        self.adaptive = adaptive
    }

    func makeWorkout(exerciseID: ExerciseID?, routineID: UUID?) -> WorkoutCoachModel {
        let plan = routineID.flatMap { id in
            try? routines?.list().first(where: { $0.id == id })?.plan(in: exerciseCatalog.all)
        }
        return makeModel(exerciseID: exerciseID, plan: plan, launch: nil)
    }

    /// Today's Session: the prepared one-family prescription, run as a tiny plan.
    func makeTodaySession(launch: TodaySessionLaunch) -> WorkoutCoachModel {
        makeModel(exerciseID: launch.plan.items.first?.exerciseID, plan: launch.plan, launch: launch)
    }

    private func makeModel(exerciseID: ExerciseID?, plan: WorkoutPlan?, launch: TodaySessionLaunch?) -> WorkoutCoachModel {
        let audioTiming = AudioWorkTiming()
        let audio = WorkoutAudioSession(timing: audioTiming)
        // Sets and reps the user adjusted on the list apply here; Saved Sets bring their own.
        let exercises = ExerciseTargetStore.applying(to: exerciseCatalog.all, preferences: preferences)
        let settings = WorkoutSettings(
            restPolicy: preferences.restPolicy,
            weightUnit: preferences.weightUnit,
            startByHolding: preferences.startByHolding
        )
        let voice = WorkoutVoiceController(recognizer: OnDeviceSpeechRecognizer(timing: audioTiming),
                                           parser: VoiceCommandParser(exercises: exercises,
                                                                     preferredWeightUnit: settings.weightUnit),
                                           permissions: SystemVoicePermissions(), audio: audio)
        let camera = WorkoutCameraController()
        // Read when the workout starts, so the developer toggle applies to the next workout.
        let recorder = preferences.workoutRecordingEnabled
            ? recordings.map { WorkoutSessionRecorder(store: $0) } : nil
        return WorkoutCoachModel(camera: camera, previewProvider: camera,
                                 permission: SystemCameraPermission(), speech: SpeechCoach(audio: audio, timing: audioTiming),
                                 audio: audio, tiltMonitor: CoreMotionTiltMonitor(), voice: voice,
                                 clock: SystemClock(), scheduler: MainScheduler(), preferences: preferences,
                                 exercises: exercises, initialExercise: exerciseID ?? exercises.first?.id,
                                 plan: plan, settings: settings, recorder: recorder, audioTiming: audioTiming,
                                 adaptive: adaptive, todayLaunch: launch)
    }
}
