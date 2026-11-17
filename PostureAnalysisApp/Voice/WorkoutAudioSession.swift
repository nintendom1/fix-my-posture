import AVFoundation
import Foundation

protocol AudioSessioning: AnyObject {
    var outputs: [String] { get }
    var inputs: [String] { get }
    var category: String { get }
    var mode: String { get }
    var categoryOptions: AVAudioSession.CategoryOptions { get }
    var isOtherAudioPlaying: Bool { get }
    var secondaryAudioShouldBeSilenced: Bool { get }
    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode,
                     options: AVAudioSession.CategoryOptions) throws
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
}

private final class SystemAudioSession: AudioSessioning {
    private let session: AVAudioSession

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    var outputs: [String] { session.currentRoute.outputs.map { $0.portType.rawValue } }
    var inputs: [String] { session.currentRoute.inputs.map { $0.portType.rawValue } }
    var category: String { session.category.rawValue }
    var mode: String { session.mode.rawValue }
    var categoryOptions: AVAudioSession.CategoryOptions { session.categoryOptions }
    var isOtherAudioPlaying: Bool { session.isOtherAudioPlaying }
    var secondaryAudioShouldBeSilenced: Bool { session.secondaryAudioShouldBeSilencedHint }

    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode,
                     options: AVAudioSession.CategoryOptions) throws {
        try session.setCategory(category, mode: mode, options: options)
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        try session.setActive(active, options: options)
    }
}

/// Pure decoding of AVAudioSession notifications; the observer and tests use the same production translation.
enum WorkoutAudioNotificationTranslator {
    static func routeEvents(userInfo: [AnyHashable: Any], outputs: [String],
                            inputs: [String]) -> [AudioSessionEvent] {
        routeEvents(reason: routeReason(userInfo: userInfo), outputs: outputs, inputs: inputs)
    }

    static func routeReason(userInfo: [AnyHashable: Any]) -> Int? {
        guard let reason = integer(userInfo[AVAudioSessionRouteChangeReasonKey]), reason >= 0 else { return nil }
        return reason
    }

    static func routeEvents(reason: Int?, outputs: [String], inputs: [String]) -> [AudioSessionEvent] {
        guard let reason, reason >= 0 else { return [] }
        var events: [AudioSessionEvent] = [
            .routeDiagnostic(reason: reason, outputs: outputs, inputs: inputs)
        ]
        if let routeReason = AVAudioSession.RouteChangeReason(rawValue: UInt(reason)),
           routeReason == .newDeviceAvailable || routeReason == .oldDeviceUnavailable {
            events.append(.routeChanged)
        }
        return events
    }

    static func interruptionEvents(userInfo: [AnyHashable: Any]) -> [AudioSessionEvent]? {
        guard let rawType = unsignedInteger(userInfo[AVAudioSessionInterruptionTypeKey]),
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return nil }
        let reason = integer(userInfo[AVAudioSessionInterruptionReasonKey])
        let wasSuspended = userInfo[AVAudioSessionInterruptionWasSuspendedKey] as? Bool ?? false
        switch type {
        case .began:
            return [
                .interruptionDiagnostic(type: "began", reason: reason,
                                        wasSuspended: wasSuspended, shouldResume: nil),
                .interruptionBegan
            ]
        case .ended:
            let rawOptions = unsignedInteger(userInfo[AVAudioSessionInterruptionOptionKey]) ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
            return [
                .interruptionDiagnostic(type: "ended", reason: reason,
                                        wasSuspended: wasSuspended, shouldResume: shouldResume),
                .interruptionEnded(shouldResume: shouldResume)
            ]
        @unknown default:
            return nil
        }
    }

    private static func unsignedInteger(_ value: Any?) -> UInt? {
        if let value = value as? UInt { return value }
        guard let value = value as? Int, value >= 0 else { return nil }
        return UInt(value)
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? UInt { return Int(exactly: value) }
        return nil
    }
}

/// Owns the shared audio session during a workout. Other audio keeps playing and is
/// lowered only while the coach speaks.
///
/// With voice control the category is `.playAndRecord` and the session stays active between
/// utterances so the microphone can listen. Speech is half-duplex: listening stops before the
/// coach speaks, because ducking only takes effect when the session is activated and other audio
/// is only restored when it is deactivated.
@MainActor
final class WorkoutAudioSession: AudioSessionControlling {
    typealias Event = AudioSessionEvent

    private let worker: WorkoutAudioSessionWorker
    private var observers: [NSObjectProtocol] = []
    private(set) var isDucking = false
    private(set) var isActive = false
    private(set) var isRecordingEnabled = false
    /// Intent is tracked separately because a queued session operation has not completed yet.
    private var requestedDucking = false
    private var duckingGeneration = 0
    var onEvent: ((Event) -> Void)?
    private let timing: AudioWorkTiming?
    private var pendingOperations: [PendingOperation] = []
    private var isProcessingOperation = false

    /// Deactivation can report busy while the synthesizer releases output; retry briefly so other
    /// audio is never left lowered.
    static let restoreRetryDelay = AudioSessionRestorePolicy.retryDelay
    static let maximumRestoreAttempts = AudioSessionRestorePolicy.maximumAttempts

    init(timing: AudioWorkTiming? = nil, session: (any AudioSessioning)? = nil) {
        self.timing = timing
        worker = WorkoutAudioSessionWorker(session: session ?? SystemAudioSession())
        observe(AVAudioSession.interruptionNotification) { [weak self] notification in
            guard let self,
                  let events = WorkoutAudioNotificationTranslator.interruptionEvents(
                    userInfo: notification.userInfo ?? [:]) else { return }
            let interruptionBegan = events.contains(.interruptionBegan)
            if interruptionBegan {
                // The system already deactivated the session; queue the matching state transition.
                self.isDucking = false
                self.isActive = false
                self.requestedDucking = false
                self.duckingGeneration += 1
            }
            self.enqueue(.interruption(events: events, began: interruptionBegan))
        }
        observe(AVAudioSession.routeChangeNotification) { [weak self] notification in
            guard let self else { return }
            let reason = WorkoutAudioNotificationTranslator.routeReason(userInfo: notification.userInfo ?? [:])
            self.enqueue(.routeChange(reason: reason))
        }
        observe(AVAudioSession.mediaServicesWereResetNotification) { [weak self] _ in
            guard let self else { return }
            self.isDucking = false
            self.isActive = false
            self.requestedDucking = false
            self.duckingGeneration += 1
            self.enqueue(.mediaServicesWereReset(recordingEnabled: self.isRecordingEnabled))
        }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// Sets the non-ducking category without activating, so nothing is interrupted.
    func configureBaseCategory() {
        enqueue(.configureBaseCategory(recordingEnabled: isRecordingEnabled))
    }

    func setRecordingEnabled(_ enabled: Bool) {
        guard enabled != isRecordingEnabled else { return }
        isRecordingEnabled = enabled
        enqueue(.setRecordingEnabled(enabled))
    }

    /// Compatibility entry point. Production callers use the completion form so recognition starts
    /// only after the background session activation has finished.
    func activateForListening() -> Bool {
        activateForListening { _ in }
        return true
    }

    func activateForListening(completion: @escaping @MainActor (Bool) -> Void) {
        enqueue(.activateForListening) { result in completion(result.activationSucceeded ?? false) }
    }

    /// Stops keeping the session active for the microphone and releases it unless the coach is speaking.
    func stopListening() {
        enqueue(.stopListening)
    }

    /// Lowers other audio. Listening must already be stopped. Speech starts after the request completes.
    func beginDucking() {
        requestBeginDucking(completion: nil)
    }

    func beginDucking(completion: @escaping @MainActor () -> Void) {
        requestBeginDucking(completion: completion)
    }

    private func requestBeginDucking(completion: (@MainActor () -> Void)?) {
        if requestedDucking {
            if let completion { enqueue(.barrier) { _ in completion() } }
            return
        }
        requestedDucking = true
        duckingGeneration += 1
        enqueue(.beginDucking, duckingGeneration: duckingGeneration) { _ in completion?() }
    }

    /// Restores other audio, then re-activates for listening if needed. Idempotent; safe from every
    /// completion, error, and teardown path.
    func endDucking() {
        requestEndDucking(completion: nil)
    }

    func endDucking(completion: @escaping @MainActor () -> Void) {
        requestEndDucking(completion: completion)
    }

    private func requestEndDucking(completion: (@MainActor () -> Void)?) {
        guard requestedDucking else {
            if let completion { enqueue(.barrier) { _ in completion() } }
            return
        }
        requestedDucking = false
        duckingGeneration += 1
        enqueue(.endDucking, duckingGeneration: duckingGeneration) { _ in completion?() }
    }

    /// Ends ducking and releases the session when leaving the workout.
    func deactivate() {
        requestedDucking = false
        duckingGeneration += 1
        enqueue(.deactivate, duckingGeneration: duckingGeneration)
    }

    func deactivate(completion: @escaping @MainActor () -> Void) {
        requestedDucking = false
        duckingGeneration += 1
        enqueue(.deactivate, duckingGeneration: duckingGeneration) { _ in completion() }
    }

    /// Waits until all session requests made before this call have completed.
    func waitForPendingSessionWork() async {
        await withCheckedContinuation { continuation in
            enqueue(.barrier) { _ in continuation.resume() }
        }
    }

    private func enqueue(_ command: AudioSessionCommand,
                         duckingGeneration operationGeneration: Int? = nil,
                         completion: (@MainActor (AudioSessionWorkerResult) -> Void)? = nil) {
        pendingOperations.append(PendingOperation(command: command, duckingGeneration: operationGeneration,
                                                   completion: completion))
        processNextOperation()
    }

    private func processNextOperation() {
        guard !isProcessingOperation, !pendingOperations.isEmpty else { return }
        isProcessingOperation = true
        let operation = pendingOperations.removeFirst()
        let worker = worker
        Task { [weak self] in
            let result = await worker.perform(operation.command)
            guard let self else { return }
            self.isDucking = result.isDucking
            self.isActive = result.isActive
            if let operationGeneration = operation.duckingGeneration,
               operationGeneration == self.duckingGeneration {
                self.requestedDucking = result.isDucking
            }
            result.measurements.forEach {
                self.timing?.record($0.step, duration: $0.duration, executionContext: $0.executionContext)
            }
            result.events.forEach { self.onEvent?($0) }
            if result.didReactivate { self.onEvent?(.reactivated) }
            operation.completion?(result)
            if result.shouldRetry { self.scheduleRestoreRetry() }
            self.isProcessingOperation = false
            self.processNextOperation()
        }
    }

    private func scheduleRestoreRetry() {
        Task { [weak self] in
            let delay = UInt64(Self.restoreRetryDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self else { return }
            self.enqueue(.retryRestore)
        }
    }

    private func observe(_ name: Notification.Name, handler: @escaping @MainActor (Notification) -> Void) {
        // The system posts these from the shared AVAudioSession, never from the injected wrapper.
        observers.append(NotificationCenter.default.addObserver(forName: name, object: AVAudioSession.sharedInstance(),
                                                                queue: .main) { notification in
            MainActor.assumeIsolated { handler(notification) }
        })
    }
}

private struct PendingOperation {
    let command: AudioSessionCommand
    let duckingGeneration: Int?
    let completion: (@MainActor (AudioSessionWorkerResult) -> Void)?
}

private enum AudioSessionCommand: Sendable {
    case configureBaseCategory(recordingEnabled: Bool)
    case setRecordingEnabled(Bool)
    case activateForListening
    case stopListening
    case beginDucking
    case endDucking
    case deactivate
    case interruption(events: [AudioSessionEvent], began: Bool)
    case mediaServicesWereReset(recordingEnabled: Bool)
    case routeChange(reason: Int?)
    case retryRestore
    case barrier
}

private struct AudioSessionMeasurement: Sendable {
    let step: AudioWorkStep
    let duration: TimeInterval
    let executionContext: AudioWorkExecutionContext
}

private struct AudioSessionWorkerResult: Sendable {
    let isDucking: Bool
    let isActive: Bool
    let activationSucceeded: Bool?
    let didReactivate: Bool
    let shouldRetry: Bool
    let events: [AudioSessionEvent]
    let measurements: [AudioSessionMeasurement]
}

/// Owns every AVAudioSession read and mutation. The MainActor facade submits one request at a time,
/// preserving caller order while this actor performs blocking framework work away from the UI executor.
private actor WorkoutAudioSessionWorker {
    private let session: any AudioSessioning
    private var isDucking = false
    private var isActive = false
    private var isRecordingEnabled = false
    private var keepsActive = false
    private var restoreAttempt = 0
    private var events: [AudioSessionEvent] = []
    private var measurements: [AudioSessionMeasurement] = []
    private var shouldRetry = false
    private var didReactivate = false
    private var activationSucceeded: Bool?

    init(session: any AudioSessioning) {
        self.session = session
    }

    func perform(_ command: AudioSessionCommand) -> AudioSessionWorkerResult {
        events = []
        measurements = []
        shouldRetry = false
        didReactivate = false
        activationSucceeded = nil

        switch command {
        case .configureBaseCategory(let recordingEnabled):
            isRecordingEnabled = recordingEnabled
            configureBaseCategory()
        case .setRecordingEnabled(let enabled):
            isRecordingEnabled = enabled
            if !isDucking { configureBaseCategory() }
        case .activateForListening:
            activationSucceeded = measured(.activateForListening) { activateSessionForListening() }
        case .stopListening:
            keepsActive = false
            guard !isDucking, isActive else { break }
            measured(.stopListening) {
                _ = setActive(false, options: .notifyOthersOnDeactivation)
                isActive = false
            }
        case .beginDucking:
            guard !isDucking else { break }
            measured(.beginDucking) { duck() }
        case .endDucking:
            endDucking()
        case .deactivate:
            keepsActive = false
            endDucking()
            measured(.deactivate) {
                _ = setActive(false, options: .notifyOthersOnDeactivation)
                isActive = false
            }
            restoreAttempt = 0
        case .interruption(let interruptionEvents, let began):
            if began {
                isDucking = false
                isActive = false
            }
            events += interruptionEvents
        case .mediaServicesWereReset(let recordingEnabled):
            isRecordingEnabled = recordingEnabled
            isDucking = false
            isActive = false
            configureBaseCategory()
            events.append(.mediaServicesReset)
        case .routeChange(let reason):
            events += WorkoutAudioNotificationTranslator.routeEvents(
                reason: reason, outputs: session.outputs, inputs: session.inputs)
        case .retryRestore:
            guard !isDucking, restoreAttempt > 0 else { break }
            restoreOtherAudio()
        case .barrier:
            break
        }

        return AudioSessionWorkerResult(isDucking: isDucking, isActive: isActive,
                                        activationSucceeded: activationSucceeded, didReactivate: didReactivate,
                                        shouldRetry: shouldRetry, events: events, measurements: measurements)
    }

    private var category: AVAudioSession.Category { isRecordingEnabled ? .playAndRecord : .playback }

    private var baseOptions: AVAudioSession.CategoryOptions {
        // A2DP keeps music in Bluetooth headphones high quality; the built-in mic does the listening.
        isRecordingEnabled ? [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP] : [.mixWithOthers]
    }

    private func configureBaseCategory() {
        try? setCategory(category, mode: .default, options: baseOptions)
    }

    private func activateSessionForListening() -> Bool {
        keepsActive = true
        guard !isDucking else { return false }
        configureBaseCategory()
        return setActive(true)
    }

    private func duck() {
        restoreAttempt = 0
        if isActive {
            _ = setActive(false)
            isActive = false
        }
        do {
            try setCategory(category, mode: .default, options: baseOptions.union(.duckOthers))
            isDucking = true
            guard setActive(true) else { throw AudioSessionActivationError.failed }
            isActive = true
        } catch {
            endDucking()
        }
    }

    private func endDucking() {
        guard isDucking else { return }
        isDucking = false
        restoreAttempt = 0
        restoreOtherAudio()
    }

    private func restoreOtherAudio() {
        let outcome = measured(.restoreOtherAudio) { attemptRestore() }
        shouldRetry = shouldRetry || outcome.shouldRetry
        didReactivate = didReactivate || outcome.didReactivate
    }

    private func attemptRestore() -> RestoreOutcome {
        do {
            try performSetActive(false, options: .notifyOthersOnDeactivation)
            isActive = false
            configureBaseCategory()
            if keepsActive {
                let activated = setActive(true)
                return RestoreOutcome(shouldRetry: false,
                                      didReactivate: activated && restoreAttempt > 0)
            }
        } catch {
            restoreAttempt += 1
            guard restoreAttempt < AudioSessionRestorePolicy.maximumAttempts else {
                configureBaseCategory()
                return RestoreOutcome(shouldRetry: false, didReactivate: false)
            }
            return RestoreOutcome(shouldRetry: true, didReactivate: false)
        }
        return RestoreOutcome(shouldRetry: false, didReactivate: false)
    }

    private func measured<T>(_ step: AudioWorkStep, _ work: () -> T) -> T {
        let start = ProcessInfo.processInfo.systemUptime
        defer {
            measurements.append(AudioSessionMeasurement(step: step,
                                                         duration: ProcessInfo.processInfo.systemUptime - start,
                                                         executionContext: .worker))
        }
        return work()
    }

    private func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode,
                             options: AVAudioSession.CategoryOptions) throws {
        events.append(.sessionOperation(operation: "setCategory", active: nil,
                                        category: category.rawValue, mode: mode.rawValue,
                                        categoryOptions: categoryOptionNames(options), activeOptions: [],
                                        isOtherAudioPlaying: session.isOtherAudioPlaying,
                                        secondaryAudioShouldBeSilenced: session.secondaryAudioShouldBeSilenced))
        try session.setCategory(category, mode: mode, options: options)
    }

    private func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions = []) -> Bool {
        do {
            try performSetActive(active, options: options)
            isActive = active
            return true
        } catch {
            return false
        }
    }

    private func performSetActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        events.append(.sessionOperation(operation: "setActive", active: active,
                                        category: session.category, mode: session.mode,
                                        categoryOptions: categoryOptionNames(session.categoryOptions),
                                        activeOptions: activeOptionNames(options),
                                        isOtherAudioPlaying: session.isOtherAudioPlaying,
                                        secondaryAudioShouldBeSilenced: session.secondaryAudioShouldBeSilenced))
        try session.setActive(active, options: options)
    }

    private func categoryOptionNames(_ options: AVAudioSession.CategoryOptions) -> [String] {
        let known: [(AVAudioSession.CategoryOptions, String)] = [
            (.mixWithOthers, "mixWithOthers"),
            (.duckOthers, "duckOthers"),
            (.allowBluetooth, "allowBluetoothHFP"),
            (.defaultToSpeaker, "defaultToSpeaker"),
            (.interruptSpokenAudioAndMixWithOthers, "interruptSpokenAudioAndMixWithOthers"),
            (.allowBluetoothA2DP, "allowBluetoothA2DP"),
            (.allowAirPlay, "allowAirPlay"),
            (.overrideMutedMicrophoneInterruption, "overrideMutedMicrophoneInterruption")
        ]
        return known.compactMap { options.contains($0.0) ? $0.1 : nil }
    }

    private func activeOptionNames(_ options: AVAudioSession.SetActiveOptions) -> [String] {
        options.contains(.notifyOthersOnDeactivation) ? ["notifyOthersOnDeactivation"] : []
    }
}

private struct RestoreOutcome {
    let shouldRetry: Bool
    let didReactivate: Bool
}

private enum AudioSessionRestorePolicy {
    static let retryDelay: TimeInterval = 0.25
    static let maximumAttempts = 4
}

private enum AudioSessionActivationError: Error {
    case failed
}
