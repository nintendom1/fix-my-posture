import AVFoundation
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class SpeechActivityTraceTests: XCTestCase {
    func testModelSpeechActivityPausesAndResumesListeningInOrder() {
        assertTrace(SpeechActivityGoldenTraces.shortTimedHold, makeShortTimedHoldTrace)
    }

    func testControllerAndAudioSessionRespondInOrderToCoachSpeakingState() {
        assertTrace(SpeechActivityGoldenTraces.controllerAudioResponseToCoachSpeakingState,
                    makeControllerAudioResponseTrace)
    }

    func testModelInterruptionStopsVoiceBeforeSpeechAndResumeHonorsSystemDecision() {
        let subject = makeModelAudioSubject()
        subject.openAndStartWorkout()

        let interruptionStart = subject.trace.lines.count
        subject.audio.emit(.interruptionBegan)

        XCTAssertEqual(subject.model.session.phase, .paused(.interruption))
        XCTAssertEqual(subject.voice.status, .paused)
        assertOrdered(["recognizer stop", "audio stopListening", "speech stopAll"],
                      in: Array(subject.trace.lines.dropFirst(interruptionStart)))
        subject.speech.finishSpeaking()

        let recognizerStarts = subject.recognizer.calls.filter { $0 == "start" }.count
        subject.audio.emit(.interruptionEnded(shouldResume: false))
        XCTAssertEqual(subject.recognizer.calls.filter { $0 == "start" }.count, recognizerStarts)
        subject.speech.finishSpeaking()

        let resumeTraceStart = subject.trace.lines.count
        subject.audio.emit(.interruptionEnded(shouldResume: true))
        XCTAssertEqual(subject.recognizer.calls.filter { $0 == "start" }.count, recognizerStarts + 1)
        assertOrdered(["audio recordingEnabled true", "audio activateForListening", "recognizer start"],
                      in: Array(subject.trace.lines.dropFirst(resumeTraceStart)))
    }

    func testModelInterruptionResumeRequiresCaptureAndAnUnmutedMicrophone() {
        let muted = makeModelAudioSubject()
        muted.openAndStartWorkout()
        muted.audio.emit(.interruptionBegan)
        muted.speech.finishSpeaking()
        muted.model.setMicMuted(true)
        let mutedStartCount = muted.recognizer.calls.filter { $0 == "start" }.count

        muted.audio.emit(.interruptionEnded(shouldResume: true))

        XCTAssertEqual(muted.recognizer.calls.filter { $0 == "start" }.count, mutedStartCount)
        XCTAssertEqual(muted.voice.status, .muted)

        let inactive = makeModelAudioSubject()
        inactive.openAndStartWorkout()
        inactive.audio.emit(.interruptionBegan)
        inactive.speech.finishSpeaking()
        inactive.model.setApplicationActive(false)
        let inactiveStartCount = inactive.recognizer.calls.filter { $0 == "start" }.count

        inactive.audio.emit(.interruptionEnded(shouldResume: true))

        XCTAssertEqual(inactive.recognizer.calls.filter { $0 == "start" }.count, inactiveStartCount)
        XCTAssertEqual(inactive.voice.status, .paused)
    }

    func testModelMediaResetStopsSpeechThenRebuildsAndRestartsRecognizer() {
        let subject = makeModelAudioSubject()
        subject.openAndStartWorkout()
        let resetStart = subject.trace.lines.count

        subject.audio.emit(.mediaServicesReset)

        assertOrdered(["speech stopAll", "recognizer stop", "recognizer rebuild", "audio activateForListening",
                       "recognizer start"],
                      in: Array(subject.trace.lines.dropFirst(resetStart)))
        XCTAssertEqual(subject.voice.status, .listening)
    }

    func testModelForwardsRouteChangeAndReactivationToVoiceControllerInOrder() {
        let subject = makeModelAudioSubject()
        subject.openAndStartWorkout()
        let eventStart = subject.trace.lines.count

        subject.audio.emit(.routeChanged)
        subject.recognizer.emit(.unavailable("route recovery"))
        subject.audio.emit(.reactivated)

        assertOrdered(["recognizer reconfigureInput", "audio stopListening", "audio activateForListening",
                       "recognizer start"],
                      in: Array(subject.trace.lines.dropFirst(eventStart)))
        XCTAssertEqual(Array(subject.recognizer.calls.suffix(2)), ["reconfigureInput", "start"])
        XCTAssertEqual(subject.voice.status, .listening)
    }

    func testModelLifecycleReleasesMicrophoneAndLateSpeechFinishDoesNotRestartIt() {
        let subject = makeModelAudioSubject()
        subject.openAndStartWorkout()
        let lifecycleStart = subject.trace.lines.count
        let recognizerStarts = subject.recognizer.calls.filter { $0 == "start" }.count
        subject.speech.speak(Utterance(text: "Lifecycle trace", isInstruction: false))

        subject.model.onDisappear()

        let lifecycleLines = Array(subject.trace.lines.dropFirst(lifecycleStart))
        assertOrdered(["recognizer stop", "audio stopListening", "speech stopAll", "audio deactivate"],
                      in: lifecycleLines)
        XCTAssertEqual(subject.recognizer.calls.filter { $0 == "start" }.count, recognizerStarts)
        guard let audioRelease = lifecycleLines.firstIndex(where: { $0.contains("audio stopListening") }) else {
            return XCTFail("The lifecycle trace must release the microphone.")
        }
        XCTAssertFalse(lifecycleLines.dropFirst(audioRelease + 1).contains(where: { $0.contains("recognizer start") }))
        XCTAssertEqual(subject.audio.calls.last, .deactivate)
    }

    private func assertTrace(_ golden: String, _ makeTrace: ((any WorkoutObserving)?) -> [String], file: StaticString = #filePath,
                             line: UInt = #line) {
        let actual = makeTrace(nil)
        let repeated = makeTrace(nil)
        XCTAssertEqual(repeated, actual, "The activity trace must be deterministic.", file: file, line: line)
        let recordingTrace = makeTrace(WorkoutObservationRecorder())
        XCTAssertEqual(recordingTrace, actual, "A recording observer changed the activity trace.", file: file, line: line)
        let heavyTrace = makeTrace(WorkoutObservationRecorder(doesHeavyWork: true))
        XCTAssertEqual(heavyTrace, actual, "A heavy observer changed the activity trace.", file: file, line: line)

        let environment = ProcessInfo.processInfo.environment
        if environment["TEST_RUNNER_FMP_GOLDEN_PRINT"] == "1" || environment["FMP_GOLDEN_PRINT"] == "1" {
            print("SPEECH_ACTIVITY_TRACE_BEGIN")
            print(actual.map { "        \($0)" }.joined(separator: "\n"))
            print("SPEECH_ACTIVITY_TRACE_END")
        }
        let expected = golden.isEmpty ? [] : golden.components(separatedBy: "\n")
        XCTAssertEqual(actual, expected, "Speech activity trace differs from its golden.", file: file, line: line)
    }

    private func makeShortTimedHoldTrace(observer: (any WorkoutObserving)?) -> [String] {
        let trace = WorkoutTraceRecorder()
        var exercise = ShoulderPressExercise.definition()
        exercise.tracking = .selfReported
        exercise.doseUnit = .seconds
        exercise.sets = 1
        exercise.targetReps = 1...1
        exercise.autoCompleteReps = 1
        exercise.targetRangeAnnouncementReps = nil
        let preferences = InMemoryPreferences()
        preferences.workoutCoachVoiceTipSpoken = true
        preferences.workoutCoachCoachMuted = false
        preferences.workoutCoachMicMuted = false
        let harness = WorkoutCoachHarness.make(preferences: preferences, exercises: [exercise],
                                               initialExercise: .shoulderPress, trace: trace, observer: observer)
        harness.speech.reportsActivity = true

        trace.input("appear (app active)")
        harness.model.onAppear(isApplicationActive: true)
        trace.input("camera running")
        harness.camera.emit(.running)
        harness.speech.finishSpeaking()

        trace.input("voice status listening")
        harness.voice.status = .listening
        harness.speech.finishSpeaking()
        trace.input("send .start")
        harness.model.send(.start)
        harness.speech.finishSpeaking()
        trace.input("advance 1.1s")
        harness.scheduler.advance(by: 1.1)
        harness.speech.finishSpeaking()
        trace.input("send .endWorkout")
        harness.model.send(.endWorkout)
        harness.speech.finishSpeaking()

        XCTAssertEqual(harness.model.session.phase, .ended)
        return trace.finish()
    }

    private func makeControllerAudioResponseTrace(observer _: (any WorkoutObserving)?) -> [String] {
        let trace = WorkoutTraceRecorder()
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        trace.now = { clock.now }
        let recorder = TraceAudioSessioning(trace: trace)
        let audio = WorkoutAudioSession(session: recorder)
        let recognizer = FakeSpeechRecognizer()
        recognizer.trace = trace
        let permissions = GrantedVoicePermissions()
        let controller = WorkoutVoiceController(
            recognizer: recognizer,
            parser: VoiceCommandParser(exercises: [AirSquatExercise.definition()]),
            permissions: permissions,
            audio: audio,
            clock: { clock.now },
            scheduler: scheduler
        )
        controller.onHeard = { trace.record("heard \(WorkoutTraceRecorder.quoted($0))") }
        controller.onCommand = { command in
            trace.record("command \(WorkoutTraceRecorder.describe(command))")
            trace.input("test supplies coach-speaking state: response begins")
            controller.setCoachSpeaking(true)
            audio.beginDucking()
            trace.input("test supplies coach-speaking state: response ends")
            audio.endDucking()
            controller.setCoachSpeaking(false)
        }

        controller.enable()
        trace.input("test supplies coach-speaking state: greeting begins")
        controller.setCoachSpeaking(true)
        audio.beginDucking()
        trace.input("test supplies coach-speaking state: greeting ends")
        audio.endDucking()
        controller.setCoachSpeaking(false)
        recognizer.transcribe("start", isFinal: true)

        return trace.finish()
    }

    private func makeModelAudioSubject() -> ModelAudioSubject {
        let trace = WorkoutTraceRecorder()
        let clock = ManualClock(now: 10)
        let scheduler = ManualScheduler(clock: clock)
        let camera = FakePoseFrameSource()
        let permission = FakeCameraPermission(status: .authorized)
        let speech = FakeSpeechCoach()
        speech.reportsActivity = true
        speech.trace = trace
        let audio = FakeAudioSession()
        audio.trace = trace
        let recognizer = FakeSpeechRecognizer()
        recognizer.trace = trace
        let voice = WorkoutVoiceController(
            recognizer: recognizer,
            parser: VoiceCommandParser(exercises: [AirSquatExercise.definition()]),
            permissions: GrantedVoicePermissions(),
            audio: audio,
            clock: { clock.now },
            scheduler: scheduler
        )
        let preferences = InMemoryPreferences()
        preferences.workoutCoachVoiceTipSpoken = true
        preferences.workoutCoachCoachMuted = false
        preferences.workoutCoachMicMuted = false
        let model = WorkoutCoachModel(
            camera: camera,
            previewProvider: nil,
            permission: permission,
            speech: speech,
            audio: audio,
            tiltMonitor: FakeTiltMonitor(),
            voice: voice,
            clock: clock,
            scheduler: scheduler,
            preferences: preferences,
            exercises: [AirSquatExercise.definition()],
            initialExercise: .airSquat,
            plan: nil,
            recorder: trace
        )
        trace.now = { clock.now }
        trace.state = { [weak model] in model.map(WorkoutTraceRecorder.state(of:)) ?? [] }
        return ModelAudioSubject(model: model, camera: camera, speech: speech, audio: audio, voice: voice,
                                 recognizer: recognizer, trace: trace)
    }

    private func assertOrdered(_ fragments: [String], in lines: [String], file: StaticString = #filePath,
                               line: UInt = #line) {
        var next = lines.startIndex
        for fragment in fragments {
            guard let found = lines[next...].firstIndex(where: { $0.contains(fragment) }) else {
                XCTFail("Missing ordered trace entry: \(fragment). Trace: \(lines)", file: file, line: line)
                return
            }
            next = lines.index(after: found)
        }
    }
}

@MainActor
private struct ModelAudioSubject {
    let model: WorkoutCoachModel
    let camera: FakePoseFrameSource
    let speech: FakeSpeechCoach
    let audio: FakeAudioSession
    let voice: WorkoutVoiceController
    let recognizer: FakeSpeechRecognizer
    let trace: WorkoutTraceRecorder

    func openAndStartWorkout() {
        model.onAppear(isApplicationActive: true)
        camera.emit(.running)
        speech.finishSpeaking()
        model.send(.start)
        speech.finishSpeaking()
    }
}

@MainActor
private struct GrantedVoicePermissions: VoicePermissionProviding {
    var microphone: VoicePermissionStatus { .granted }
    var speechRecognition: VoicePermissionStatus { .granted }
    func requestMicrophone(_ completion: @escaping @MainActor (Bool) -> Void) { completion(true) }
    func requestSpeechRecognition(_ completion: @escaping @MainActor (Bool) -> Void) { completion(true) }
}

@MainActor
private final class TraceAudioSessioning: AudioSessioning {
    private let trace: WorkoutTraceRecorder
    private(set) var category = AVAudioSession.Category.playback.rawValue
    private(set) var mode = AVAudioSession.Mode.default.rawValue
    private(set) var categoryOptions: AVAudioSession.CategoryOptions = [.mixWithOthers]
    let outputs = ["BuiltInSpeaker"]
    let inputs = ["BuiltInMic"]
    let isOtherAudioPlaying = true
    let secondaryAudioShouldBeSilenced = false

    init(trace: WorkoutTraceRecorder) {
        self.trace = trace
    }

    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode,
                     options: AVAudioSession.CategoryOptions) throws {
        let optionsText = Self.categoryOptionNames(options).joined(separator: ",")
        trace.record("audio category \(category.rawValue) mode=\(mode.rawValue) " +
                     "optionsRaw=\(options.rawValue) names=\(optionsText)")
        self.category = category.rawValue
        self.mode = mode.rawValue
        categoryOptions = options
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        let option = options.contains(.notifyOthersOnDeactivation) ? " notifyOthersOnDeactivation" : ""
        trace.record("audio active \(active)\(option)")
    }

    private static func categoryOptionNames(_ options: AVAudioSession.CategoryOptions) -> [String] {
        let known: [(AVAudioSession.CategoryOptions, String)] = [
            (.duckOthers, "duckOthers"), (.mixWithOthers, "mixWithOthers"),
            (.defaultToSpeaker, "defaultToSpeaker"), (.allowBluetooth, "allowBluetooth"),
            (.allowBluetoothA2DP, "allowBluetoothA2DP"), (.allowAirPlay, "allowAirPlay"),
            (.interruptSpokenAudioAndMixWithOthers, "interruptSpokenAudioAndMixWithOthers")
        ]
        return known.compactMap { options.contains($0.0) ? $0.1 : nil }.sorted()
    }
}
