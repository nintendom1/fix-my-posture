import AdaptiveTraining
import Foundation
@testable import PostureAnalysisApp

final class FakePoseFrameSource: PoseFrameSource {
    private(set) var starts = 0
    private(set) var stops = 0
    private var generation: UUID?
    private var receive: PoseFrameReceiver?

    func start(generation: UUID, receive: @escaping PoseFrameReceiver) {
        starts += 1
        self.generation = generation
        self.receive = receive
    }

    func stop() {
        stops += 1
        generation = nil
        receive = nil
    }

    @MainActor func emit(_ event: PoseFrameSourceEvent) {
        guard let generation else { return }
        receive?(generation, event)
    }
}

@MainActor
final class FakeCameraPermission: CameraPermissionProviding {
    var status: CameraAuthorization
    private(set) var completion: (@MainActor (Bool) -> Void)?

    init(status: CameraAuthorization) {
        self.status = status
    }

    func request(_ completion: @escaping @MainActor (Bool) -> Void) {
        self.completion = completion
    }

    func complete(granted: Bool) {
        status = granted ? .authorized : .denied
        completion?(granted)
        completion = nil
    }
}

@MainActor
final class FakeSpeechCoach: SpeechCoaching {
    private(set) var utterances: [Utterance] = []
    private(set) var stopCount = 0
    private(set) var repeatCount = 0
    private(set) var isSpeaking = false
    /// Activity callbacks are opt-in so older model tests keep their original behavior.
    var reportsActivity = false
    var onActivityChanged: ((Bool) -> Void)?
    /// Golden traces only: every call is also written here.
    var trace: WorkoutTraceRecorder?

    func speak(_ utterance: Utterance) {
        if reportsActivity, !isSpeaking {
            isSpeaking = true
            trace?.beginSpeechActivityCallback()
            onActivityChanged?(true)
            trace?.endSpeechActivityCallback()
        }
        utterances.append(utterance)
        trace?.speechSpoke(utterance)
    }

    func finishSpeaking() {
        guard reportsActivity, isSpeaking else { return }
        isSpeaking = false
        onActivityChanged?(false)
    }

    func repeatLastInstruction() {
        repeatCount += 1
        trace?.speechRepeated(lastInstruction: utterances.last(where: \.isInstruction))
    }

    func stopAll() {
        stopCount += 1
        trace?.record("speech stopAll")
        finishSpeaking()
    }
}

@MainActor
final class FakeSpeechRecognizer: SpeechRecognizing {
    var onTranscript: ((_ text: String, _ isFinal: Bool) -> Void)?
    var onStateChanged: ((SpeechRecognizerState) -> Void)?
    private(set) var contextualStrings: [String] = []
    private(set) var calls: [String] = []
    var reportsListeningOnStart = true
    var trace: WorkoutTraceRecorder?

    func setContextualStrings(_ strings: [String]) {
        contextualStrings = strings
    }

    func start() {
        calls.append("start")
        trace?.record("recognizer start")
        if reportsListeningOnStart { onStateChanged?(.listening) }
    }

    func stop() {
        calls.append("stop")
        trace?.record("recognizer stop")
        onStateChanged?(.idle)
    }

    func restartTask() {
        calls.append("restartTask")
        trace?.record("recognizer restartTask")
    }

    func reconfigureInput() {
        calls.append("reconfigureInput")
        trace?.record("recognizer reconfigureInput")
    }

    func rebuild() {
        calls.append("rebuild")
        trace?.record("recognizer rebuild")
    }

    func transcribe(_ text: String, isFinal: Bool = false) {
        onTranscript?(text, isFinal)
    }

    func emit(_ state: SpeechRecognizerState) {
        onStateChanged?(state)
    }
}

@MainActor
final class FakeAudioSession: AudioSessionControlling {
    enum Call: Equatable {
        case configureBaseCategory
        case recordingEnabled(Bool)
        case activateForListening
        case stopListening
        case beginDucking
        case endDucking
        case deactivate
    }

    var onEvent: ((AudioSessionEvent) -> Void)?
    private(set) var calls: [Call] = []
    var listeningActivationSucceeds = true
    /// Golden traces only: every call is also written here.
    var trace: WorkoutTraceRecorder?

    func configureBaseCategory() {
        calls.append(.configureBaseCategory)
        trace?.record("audio configureBaseCategory")
    }
    func setRecordingEnabled(_ enabled: Bool) {
        calls.append(.recordingEnabled(enabled))
        trace?.record("audio recordingEnabled \(enabled)")
    }
    func activateForListening() -> Bool {
        calls.append(.activateForListening)
        trace?.record("audio activateForListening -> \(listeningActivationSucceeds)")
        return listeningActivationSucceeds
    }
    func stopListening() {
        calls.append(.stopListening)
        trace?.record("audio stopListening")
    }
    func beginDucking() {
        calls.append(.beginDucking)
        trace?.record("audio beginDucking")
    }
    func endDucking() {
        calls.append(.endDucking)
        trace?.record("audio endDucking")
    }
    func deactivate() {
        calls.append(.deactivate)
        trace?.record("audio deactivate")
    }

    func emit(_ event: AudioSessionEvent) {
        onEvent?(event)
    }
}

@MainActor
final class FakeTiltMonitor: PhoneTiltMonitoring {
    var latestTilt: PhoneTilt?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
}

@MainActor
final class FakeVoiceController: VoiceControlling {
    var status: VoiceStatus = .off {
        didSet { if status != oldValue { onStatusChanged?(status) } }
    }
    var onStatusChanged: ((VoiceStatus) -> Void)?
    var onCommand: ((WorkoutCommand) -> Void)?
    var onHeard: ((String) -> Void)?
    var acceptsEffortFeedback = false {
        didSet { trace?.record("listen acceptsEffort \(acceptsEffortFeedback)") }
    }
    var onEffort: ((EffortFeedback) -> Void)?
    var acceptsBonusAnswer = false {
        didSet { trace?.record("listen acceptsBonus \(acceptsBonusAnswer)") }
    }
    var onBonus: ((BonusAnswer) -> Void)?
    private(set) var mutedValues: [Bool] = []
    private(set) var enabledCount = 0
    private(set) var retryCount = 0
    private(set) var disabledStatuses: [VoiceStatus] = []
    private(set) var coachSpeakingValues: [Bool] = []
    private(set) var audioEvents: [AudioSessionEvent] = []
    /// Golden traces only: every call is also written here.
    var trace: WorkoutTraceRecorder?

    func enable() {
        enabledCount += 1
        trace?.record("listen enable")
    }
    func disable(status: VoiceStatus) {
        disabledStatuses.append(status)
        trace?.record("listen disable \(WorkoutTraceRecorder.describe(status))")
    }
    func setMuted(_ muted: Bool) {
        mutedValues.append(muted)
        trace?.record("listen muted \(muted)")
    }
    func retry() {
        retryCount += 1
        trace?.record("listen retry")
    }
    func setCoachSpeaking(_ speaking: Bool) {
        coachSpeakingValues.append(speaking)
        trace?.record("listen coachSpeaking \(speaking)")
    }
    func handleAudioEvent(_ event: AudioSessionEvent) {
        audioEvents.append(event)
        trace?.record("listen audioEvent \(WorkoutTraceRecorder.describe(event))")
    }

    func emit(_ command: WorkoutCommand) { onCommand?(command) }
    func emitHeard(_ phrase: String) { onHeard?(phrase) }
    func emitEffort(_ effort: EffortFeedback) { onEffort?(effort) }
    func emitBonus(_ answer: BonusAnswer) { onBonus?(answer) }
}

final class ManualClock: Clock {
    private(set) var now: TimeInterval

    init(now: TimeInterval = 0) {
        self.now = now
    }

    func advance(by interval: TimeInterval) {
        now += interval
    }
}

@MainActor
final class ManualScheduler: Scheduling {
    private struct Entry {
        var fireAt: TimeInterval
        let interval: TimeInterval?
        let action: @MainActor () -> Void
    }

    private(set) var now: TimeInterval
    private let clock: ManualClock
    private var entries: [UUID: Entry] = [:]

    init(clock: ManualClock) {
        self.clock = clock
        now = clock.now
    }

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Cancellable {
        add(after: delay, interval: nil, action)
    }

    func repeating(every interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Cancellable {
        add(after: interval, interval: interval, action)
    }

    func advance(by interval: TimeInterval) {
        let target = now + interval
        while let next = entries
            .filter({ $0.value.fireAt <= target })
            .min(by: { $0.value.fireAt < $1.value.fireAt }) {
            now = next.value.fireAt
            clock.advance(by: now - clock.now)
            if let repeatInterval = next.value.interval {
                entries[next.key]?.fireAt += repeatInterval
            } else {
                entries.removeValue(forKey: next.key)
            }
            next.value.action()
        }
        clock.advance(by: target - clock.now)
        now = target
    }

    /// Fires the registered repeating actions once without advancing either clock.
    func fireRepeatingCallbacks() {
        entries.values
            .filter { $0.interval != nil }
            .sorted { $0.fireAt < $1.fireAt }
            .forEach { $0.action() }
    }

    private func add(after delay: TimeInterval, interval: TimeInterval?, _ action: @escaping @MainActor () -> Void) -> Cancellable {
        let id = UUID()
        entries[id] = Entry(fireAt: now + delay, interval: interval, action: action)
        return ManualCancellation { [weak self] in self?.entries.removeValue(forKey: id) }
    }
}

@MainActor
private final class ManualCancellation: Cancellable {
    private var cancelAction: (() -> Void)?

    init(_ cancelAction: @escaping () -> Void) {
        self.cancelAction = cancelAction
    }

    func cancel() {
        cancelAction?()
        cancelAction = nil
    }
}
