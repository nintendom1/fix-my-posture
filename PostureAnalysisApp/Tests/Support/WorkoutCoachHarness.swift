import Foundation
@testable import PostureAnalysisApp

@MainActor
final class WorkoutObservationActionLog {
    private(set) var entries: [String] = []

    func append(_ entry: String) {
        entries.append(entry)
    }

    func clear() {
        entries.removeAll()
    }
}

@MainActor
private final class WorkoutObservationLoggingSpeech: SpeechCoaching {
    private let base: FakeSpeechCoach
    private let log: WorkoutObservationActionLog

    var isSpeaking: Bool { base.isSpeaking }
    var onActivityChanged: ((Bool) -> Void)? {
        get { base.onActivityChanged }
        set { base.onActivityChanged = newValue }
    }

    init(base: FakeSpeechCoach, log: WorkoutObservationActionLog) {
        self.base = base
        self.log = log
    }

    func speak(_ utterance: Utterance) {
        log.append("speech.speak.begin: \(utterance.text)")
        base.speak(utterance)
        log.append("speech.speak.end: \(utterance.text)")
    }

    func repeatLastInstruction() {
        log.append("speech.repeat.begin")
        base.repeatLastInstruction()
        log.append("speech.repeat.end")
    }

    func stopAll() {
        log.append("speech.stop.begin")
        base.stopAll()
        log.append("speech.stop.end")
    }
}

@MainActor
private final class WorkoutObservationLoggingScheduler: Scheduling {
    private let base: ManualScheduler
    private let log: WorkoutObservationActionLog

    init(base: ManualScheduler, log: WorkoutObservationActionLog) {
        self.base = base
        self.log = log
    }

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Cancellable {
        log.append("scheduler.schedule.begin: \(delay)")
        let task = base.schedule(after: delay, action)
        log.append("scheduler.schedule.end: \(delay)")
        return task
    }

    func repeating(every interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Cancellable {
        log.append("scheduler.repeating.begin: \(interval)")
        let task = base.repeating(every: interval, action)
        log.append("scheduler.repeating.end: \(interval)")
        return task
    }
}

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
                     exercises: [ExerciseDefinition] = ExerciseCatalog.all,
                     initialExercise: ExerciseID = .shoulderPress,
                     recorder: (any WorkoutSessionRecording)? = nil,
                     audioTiming: AudioWorkTiming? = nil,
                     plan: WorkoutPlan? = nil,
                     adaptive: (any AdaptiveEvidenceRecording)? = nil,
                     todayLaunch: TodaySessionLaunch? = nil,
                     trace: WorkoutTraceRecorder? = nil,
                     observer: (any WorkoutObserving)? = nil,
                     actionLog: WorkoutObservationActionLog? = nil) -> WorkoutCoachHarness {
        let clock = ManualClock(now: 10)
        let scheduler = ManualScheduler(clock: clock)
        let schedulerService: any Scheduling
        if let actionLog {
            schedulerService = WorkoutObservationLoggingScheduler(base: scheduler, log: actionLog)
        } else {
            schedulerService = scheduler
        }
        let camera = FakePoseFrameSource()
        let permission = FakeCameraPermission(status: permissionStatus)
        let speech = FakeSpeechCoach()
        let speechService: any SpeechCoaching
        if let actionLog {
            speechService = WorkoutObservationLoggingSpeech(base: speech, log: actionLog)
        } else {
            speechService = speech
        }
        let audio = FakeAudioSession()
        let tilt = FakeTiltMonitor()
        let voice = FakeVoiceController()
        // A golden trace hears the fakes and, unless another recorder is given, is the model's session recorder too.
        speech.trace = trace
        audio.trace = trace
        voice.trace = trace
        trace?.now = { clock.now }
        let model = WorkoutCoachModel(
            camera: camera,
            previewProvider: nil,
            permission: permission,
            speech: speechService,
            audio: audio,
            tiltMonitor: tilt,
            voice: voice,
            clock: clock,
            scheduler: schedulerService,
            preferences: preferences,
            exercises: exercises,
            initialExercise: initialExercise,
            plan: plan,
            recorder: recorder ?? trace,
            audioTiming: audioTiming,
            adaptive: adaptive,
            todayLaunch: todayLaunch,
            evidenceDate: { Date(timeIntervalSince1970: 1_000) },
            observer: observer
        )
        trace?.state = { [weak model] in model.map(WorkoutTraceRecorder.state(of:)) ?? [] }
        return WorkoutCoachHarness(model: model, camera: camera, permission: permission, speech: speech,
                                   audio: audio, tilt: tilt, voice: voice, clock: clock, scheduler: scheduler)
    }
}
