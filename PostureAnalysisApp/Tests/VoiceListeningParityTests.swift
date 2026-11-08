import XCTest
@testable import PostureAnalysisApp

@MainActor
final class VoiceListeningParityTests: XCTestCase {
    func testCoachSpeechPausesListeningAcrossBackToBackLinesAndDropsPendingFinalResult() {
        let subject = makeSubject()
        subject.controller.enable()
        subject.recognizer.transcribe("start")

        subject.controller.setCoachSpeaking(true)
        // A queued line keeps the coach active. The recognizer is already stopped.
        subject.controller.setCoachSpeaking(true)
        subject.recognizer.transcribe("start", isFinal: true)
        subject.controller.setCoachSpeaking(false)

        XCTAssertEqual(subject.recognizer.calls, ["start", "stop", "start"])
        XCTAssertEqual(subject.commands, [])
        XCTAssertEqual(subject.controller.status, .listening)
    }

    func testAmbiguousStartUsesDefaultSettleBoundary() {
        let subject = makeSubject()
        subject.controller.enable()
        subject.recognizer.transcribe("start")

        subject.scheduler.advance(by: 0.59)
        XCTAssertEqual(subject.commands, [])
        subject.scheduler.advance(by: 0.02)

        XCTAssertEqual(subject.commands, [.start])
        XCTAssertEqual(subject.recognizer.calls, ["start", "restartTask"])
    }

    func testWaitSoundAlikeUsesOneSecondSettleBoundary() {
        let subject = makeSubject()
        subject.controller.enable()
        subject.recognizer.transcribe("wait")

        subject.clock.advance(by: 0.999)
        subject.scheduler.fireRepeatingCallbacks()
        XCTAssertEqual(subject.commands, [])
        subject.clock.advance(by: 0.002)
        subject.scheduler.fireRepeatingCallbacks()

        XCTAssertEqual(subject.commands, [.pause])
        XCTAssertEqual(subject.recognizer.calls, ["start", "restartTask"])
    }

    func testDisableDuringCoachSpeechDoesNotRestartAfterSpeechFinishes() {
        let trace = WorkoutTraceRecorder()
        let subject = makeSubject(trace: trace)
        subject.controller.enable()
        let traceStart = trace.lines.count

        subject.controller.setCoachSpeaking(true)
        subject.controller.disable(status: .paused)
        subject.controller.setCoachSpeaking(false)

        XCTAssertEqual(Array(trace.lines.dropFirst(traceStart)), [
            "t=0.00 recognizer stop",
            "t=0.00 audio stopListening"
        ])
        XCTAssertEqual(subject.recognizer.calls, ["start", "stop"])
        XCTAssertEqual(subject.controller.status, .paused)
    }

    func testMuteDuringCoachSpeechDoesNotRestartAfterSpeechFinishes() {
        let trace = WorkoutTraceRecorder()
        let subject = makeSubject(trace: trace)
        subject.controller.enable()
        let traceStart = trace.lines.count

        subject.controller.setCoachSpeaking(true)
        subject.controller.setMuted(true)
        subject.controller.setCoachSpeaking(false)

        XCTAssertEqual(Array(trace.lines.dropFirst(traceStart)), [
            "t=0.00 recognizer stop",
            "t=0.00 audio stopListening"
        ])
        XCTAssertEqual(subject.recognizer.calls, ["start", "stop"])
        XCTAssertEqual(subject.controller.status, .muted)
    }

    func testDisableWhileActivelyListeningStopsRecognitionBeforeAudioRelease() {
        let trace = WorkoutTraceRecorder()
        let subject = makeSubject(trace: trace)
        subject.controller.enable()
        XCTAssertEqual(subject.controller.status, .listening)
        let traceStart = trace.lines.count

        subject.controller.disable(status: .paused)

        XCTAssertEqual(Array(trace.lines.dropFirst(traceStart)), [
            "t=0.00 recognizer stop",
            "t=0.00 audio stopListening"
        ])
        XCTAssertEqual(subject.recognizer.calls, ["start", "stop"])
        XCTAssertEqual(subject.controller.status, .paused)
    }

    func testMuteWhileActivelyListeningStopsRecognitionBeforeAudioRelease() {
        let trace = WorkoutTraceRecorder()
        let subject = makeSubject(trace: trace)
        subject.controller.enable()
        XCTAssertEqual(subject.controller.status, .listening)
        let traceStart = trace.lines.count

        subject.controller.setMuted(true)

        XCTAssertEqual(Array(trace.lines.dropFirst(traceStart)), [
            "t=0.00 recognizer stop",
            "t=0.00 audio stopListening"
        ])
        XCTAssertEqual(subject.recognizer.calls, ["start", "stop"])
        XCTAssertEqual(subject.controller.status, .muted)
    }

    func testUnchangedNonCommandTranscriptRestartsAtOnePointTwoSeconds() {
        let subject = makeSubject()
        subject.controller.enable()
        subject.recognizer.transcribe("unrecognized words")

        subject.scheduler.advance(by: 1.19)
        XCTAssertEqual(subject.recognizer.calls, ["start"])
        subject.scheduler.advance(by: 0.02)

        XCTAssertEqual(subject.recognizer.calls, ["start", "restartTask"])
        subject.recognizer.transcribe("start", isFinal: true)
        XCTAssertEqual(subject.commands, [.start])
        XCTAssertEqual(subject.recognizer.calls, ["start", "restartTask", "restartTask"])
    }

    func testRecognizerFailureStopsListeningAndRetryStartsFreshRecognition() {
        let subject = makeSubject()
        subject.controller.enable()
        subject.recognizer.emit(.unavailable("recognition failed"))

        XCTAssertEqual(subject.controller.status, .unavailable("recognition failed"))
        XCTAssertEqual(subject.audio.calls, [
            .recordingEnabled(true), .activateForListening, .stopListening
        ])

        subject.controller.retry()

        XCTAssertEqual(subject.recognizer.calls, ["start", "start"])
        XCTAssertEqual(subject.controller.status, .listening)
        XCTAssertEqual(subject.audio.calls, [
            .recordingEnabled(true), .activateForListening, .stopListening,
            .recordingEnabled(true), .activateForListening
        ])
    }

    func testAudioEventsOnlyReconfigureOrRebuildRecognitionWhenApplicable() {
        let subject = makeSubject()
        subject.controller.enable()
        subject.controller.handleAudioEvent(.interruptionBegan)
        subject.controller.handleAudioEvent(.interruptionEnded(shouldResume: true))
        subject.controller.handleAudioEvent(.routeDiagnostic(reason: 3, outputs: [], inputs: []))
        subject.controller.handleAudioEvent(.routeChanged)
        subject.controller.handleAudioEvent(.mediaServicesReset)
        subject.controller.handleAudioEvent(.reactivated)
        subject.controller.setCoachSpeaking(true)
        subject.controller.handleAudioEvent(.mediaServicesReset)
        subject.controller.setCoachSpeaking(false)

        XCTAssertEqual(subject.recognizer.calls, [
            "start", "reconfigureInput", "stop", "rebuild", "start", "reconfigureInput",
            "stop", "rebuild", "start"
        ])
        XCTAssertEqual(subject.controller.status, .listening)
    }

    func testPermissionAndMuteTransitionsUpdateMicrophoneStatus() {
        let permissions = FakeVoicePermissions(microphone: .notDetermined, speechRecognition: .notDetermined)
        let subject = makeSubject(permissions: permissions)

        subject.controller.enable()
        XCTAssertEqual(subject.controller.status, .requestingPermission)
        XCTAssertEqual(permissions.requests, ["microphone"])
        permissions.completeMicrophone(true)
        XCTAssertEqual(permissions.requests, ["microphone", "speech"])
        permissions.completeSpeech(false)
        XCTAssertEqual(subject.controller.status, .needsPermission)

        permissions.speechRecognition = .granted
        subject.controller.retry()
        XCTAssertEqual(subject.controller.status, .listening)
        subject.controller.setMuted(true)
        XCTAssertEqual(subject.controller.status, .muted)
        subject.controller.setMuted(false)
        XCTAssertEqual(subject.controller.status, .off)
        subject.controller.enable()
        XCTAssertEqual(subject.controller.status, .listening)
    }

    func testDeniedMicrophoneDoesNotRequestSpeechPermission() {
        let permissions = FakeVoicePermissions(microphone: .denied, speechRecognition: .granted)
        let subject = makeSubject(permissions: permissions)

        subject.controller.enable()

        XCTAssertEqual(subject.controller.status, .needsPermission)
        XCTAssertEqual(permissions.requests, [])
        XCTAssertEqual(subject.recognizer.calls, [])
    }

    private func makeSubject(permissions: FakeVoicePermissions? = nil,
                             trace: WorkoutTraceRecorder? = nil) -> Subject {
        let clock = ManualClock()
        let scheduler = ManualScheduler(clock: clock)
        let recognizer = FakeSpeechRecognizer()
        let audio = FakeAudioSession()
        recognizer.trace = trace
        audio.trace = trace
        let permissions = permissions ?? FakeVoicePermissions()
        let controller = WorkoutVoiceController(
            recognizer: recognizer,
            parser: VoiceCommandParser(exercises: [AirSquatExercise.definition()]),
            permissions: permissions,
            audio: audio,
            clock: { clock.now },
            scheduler: scheduler
        )
        return Subject(controller: controller, recognizer: recognizer, audio: audio, scheduler: scheduler,
                       clock: clock, permissions: permissions, trace: trace, commands: [])
    }

    @MainActor
    private struct Subject {
        let controller: WorkoutVoiceController
        let recognizer: FakeSpeechRecognizer
        let audio: FakeAudioSession
        let scheduler: ManualScheduler
        let clock: ManualClock
        let permissions: FakeVoicePermissions
        let trace: WorkoutTraceRecorder?
        var commands: [WorkoutCommand] {
            commandStorage.value
        }

        // A reference box lets the controller callback collect commands while keeping this fixture a value.
        private let commandStorage: CommandStorage

        init(controller: WorkoutVoiceController, recognizer: FakeSpeechRecognizer, audio: FakeAudioSession,
             scheduler: ManualScheduler, clock: ManualClock, permissions: FakeVoicePermissions,
             trace: WorkoutTraceRecorder?, commands: [WorkoutCommand]) {
            self.controller = controller
            self.recognizer = recognizer
            self.audio = audio
            self.scheduler = scheduler
            self.clock = clock
            self.permissions = permissions
            self.trace = trace
            commandStorage = CommandStorage(commands)
            controller.onCommand = { [commandStorage] command in commandStorage.value.append(command) }
        }
    }

    @MainActor
    private final class CommandStorage {
        var value: [WorkoutCommand]
        init(_ value: [WorkoutCommand]) { self.value = value }
    }
}

@MainActor
private final class FakeVoicePermissions: VoicePermissionProviding {
    var microphone: VoicePermissionStatus
    var speechRecognition: VoicePermissionStatus
    private(set) var requests: [String] = []
    private var microphoneCompletion: (@MainActor (Bool) -> Void)?
    private var speechCompletion: (@MainActor (Bool) -> Void)?

    init(microphone: VoicePermissionStatus = .granted, speechRecognition: VoicePermissionStatus = .granted) {
        self.microphone = microphone
        self.speechRecognition = speechRecognition
    }

    func requestMicrophone(_ completion: @escaping @MainActor (Bool) -> Void) {
        requests.append("microphone")
        microphoneCompletion = completion
    }

    func requestSpeechRecognition(_ completion: @escaping @MainActor (Bool) -> Void) {
        requests.append("speech")
        speechCompletion = completion
    }

    func completeMicrophone(_ granted: Bool) {
        microphone = granted ? .granted : .denied
        microphoneCompletion?(granted)
        microphoneCompletion = nil
    }

    func completeSpeech(_ granted: Bool) {
        speechRecognition = granted ? .granted : .denied
        speechCompletion?(granted)
        speechCompletion = nil
    }
}
