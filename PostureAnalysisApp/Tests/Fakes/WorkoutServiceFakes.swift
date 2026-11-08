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
    var isSpeaking = false
    var onActivityChanged: ((Bool) -> Void)?

    func speak(_ utterance: Utterance) {
        utterances.append(utterance)
    }

    func repeatLastInstruction() {}

    func stopAll() {
        stopCount += 1
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

    func configureBaseCategory() { calls.append(.configureBaseCategory) }
    func setRecordingEnabled(_ enabled: Bool) { calls.append(.recordingEnabled(enabled)) }
    func activateForListening() -> Bool {
        calls.append(.activateForListening)
        return listeningActivationSucceeds
    }
    func stopListening() { calls.append(.stopListening) }
    func beginDucking() { calls.append(.beginDucking) }
    func endDucking() { calls.append(.endDucking) }
    func deactivate() { calls.append(.deactivate) }

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
    var acceptsEffortFeedback = false
    var onEffort: ((EffortFeedback) -> Void)?
    var acceptsBonusAnswer = false
    var onBonus: ((BonusAnswer) -> Void)?
    private(set) var mutedValues: [Bool] = []
    private(set) var enabledCount = 0
    private(set) var retryCount = 0
    private(set) var disabledStatuses: [VoiceStatus] = []
    private(set) var coachSpeakingValues: [Bool] = []
    private(set) var audioEvents: [AudioSessionEvent] = []

    func enable() { enabledCount += 1 }
    func disable(status: VoiceStatus) { disabledStatuses.append(status) }
    func setMuted(_ muted: Bool) { mutedValues.append(muted) }
    func retry() { retryCount += 1 }
    func setCoachSpeaking(_ speaking: Bool) { coachSpeakingValues.append(speaking) }
    func handleAudioEvent(_ event: AudioSessionEvent) { audioEvents.append(event) }

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
