import AVFoundation
import Foundation

@MainActor
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

@MainActor
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
        guard let reason = integer(userInfo[AVAudioSessionRouteChangeReasonKey]), reason >= 0 else { return [] }
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

    private let session: any AudioSessioning
    private var observers: [NSObjectProtocol] = []
    private(set) var isDucking = false
    private(set) var isActive = false
    private(set) var isRecordingEnabled = false
    /// Re-activate after speech so the microphone keeps listening.
    private var keepsActive = false
    var onEvent: ((Event) -> Void)?
    private var restoreAttempt = 0
    private let timing: AudioWorkTiming?

    /// Deactivation can report busy while the synthesizer releases output; retry briefly so other
    /// audio is never left lowered.
    static let restoreRetryDelay: TimeInterval = 0.25
    static let maximumRestoreAttempts = 4

    init(timing: AudioWorkTiming? = nil, session: (any AudioSessioning)? = nil) {
        self.timing = timing
        self.session = session ?? SystemAudioSession()
        observe(AVAudioSession.interruptionNotification) { [weak self] notification in
            guard let self,
                  let events = WorkoutAudioNotificationTranslator.interruptionEvents(
                    userInfo: notification.userInfo ?? [:]) else { return }
            if events.contains(.interruptionBegan) {
                // The system already deactivated the session; just forget the ducked state.
                self.isDucking = false
                self.isActive = false
            }
            events.forEach { self.onEvent?($0) }
        }
        observe(AVAudioSession.routeChangeNotification) { [weak self] notification in
            guard let self else { return }
            let events = WorkoutAudioNotificationTranslator.routeEvents(
                userInfo: notification.userInfo ?? [:], outputs: self.session.outputs, inputs: self.session.inputs)
            // Our own category changes also post route changes; only device changes matter here.
            events.forEach { self.onEvent?($0) }
        }
        observe(AVAudioSession.mediaServicesWereResetNotification) { [weak self] _ in
            guard let self else { return }
            self.isDucking = false
            self.isActive = false
            self.configureBaseCategory()
            self.onEvent?(.mediaServicesReset)
        }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private var category: AVAudioSession.Category { isRecordingEnabled ? .playAndRecord : .playback }

    private var baseOptions: AVAudioSession.CategoryOptions {
        // A2DP keeps music in Bluetooth headphones high quality; the built-in mic does the listening.
        isRecordingEnabled ? [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP] : [.mixWithOthers]
    }

    /// Sets the non-ducking category without activating, so nothing is interrupted.
    func configureBaseCategory() {
        try? setCategory(category, mode: .default, options: baseOptions)
    }

    func setRecordingEnabled(_ enabled: Bool) {
        guard enabled != isRecordingEnabled else { return }
        isRecordingEnabled = enabled
        if !isDucking { configureBaseCategory() }
    }

    /// Activates the recording category for listening. Returns false if the session can't activate.
    func activateForListening() -> Bool {
        measured(.activateForListening) { activateSessionForListening() }
    }

    private func activateSessionForListening() -> Bool {
        keepsActive = true
        guard !isDucking else { return false }
        configureBaseCategory()
        return setActive(true)
    }

    /// Stops keeping the session active for the microphone and releases it unless the coach is speaking.
    func stopListening() {
        keepsActive = false
        guard !isDucking, isActive else { return }
        measured(.stopListening) {
            _ = setActive(false, options: .notifyOthersOnDeactivation)
            isActive = false
        }
    }

    /// Lowers other audio. Listening must already be stopped. Speech still plays if this fails.
    func beginDucking() {
        guard !isDucking else { return }
        measured(.beginDucking) { duck() }
    }

    private func duck() {
        restoreAttempt = 0
        // Ducking applies on activation, so an already-active listening session is cycled first.
        if isActive {
            _ = setActive(false)
            isActive = false
        }
        do {
            try setCategory(category, mode: .default, options: baseOptions.union(.duckOthers))
            // Marked before activation so endDucking always restores the category.
            isDucking = true
            guard setActive(true) else { throw AudioSessionActivationError.failed }
            isActive = true
        } catch {
            endDucking()
        }
    }

    /// Restores other audio, then re-activates for listening if needed. Idempotent; safe from every
    /// completion, error, and teardown path.
    func endDucking() {
        guard isDucking else { return }
        isDucking = false
        restoreAttempt = 0
        restoreOtherAudio()
    }

    private func restoreOtherAudio() {
        let reactivatedLate = measured(.restoreOtherAudio) { attemptRestore() }
        // After the timing, so the recognizer work it triggers is timed on its own.
        if reactivatedLate { onEvent?(.reactivated) }
    }

    /// Returns true when a retry reactivated the session for listening.
    private func attemptRestore() -> Bool {
        do {
            try performSetActive(false, options: .notifyOthersOnDeactivation)
            isActive = false
            configureBaseCategory()
            if keepsActive {
                _ = setActive(true)
                return restoreAttempt > 0
            }
        } catch {
            restoreAttempt += 1
            guard restoreAttempt < Self.maximumRestoreAttempts else {
                configureBaseCategory()
                return false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.restoreRetryDelay) { [weak self] in
                MainActor.assumeIsolated {
                    // A new utterance started ducking again; it will restore when it finishes.
                    guard let self, !self.isDucking, self.restoreAttempt > 0 else { return }
                    self.restoreOtherAudio()
                }
            }
        }
        return false
    }

    /// Ends ducking and releases the session when leaving the workout.
    func deactivate() {
        keepsActive = false
        endDucking()
        measured(.deactivate) {
            _ = setActive(false, options: .notifyOthersOnDeactivation)
            isActive = false
        }
    }

    private func measured<T>(_ step: AudioWorkStep, _ work: () -> T) -> T {
        timing.map { $0.measure(step, work) } ?? work()
    }

    private func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode,
                             options: AVAudioSession.CategoryOptions) throws {
        onEvent?(.sessionOperation(operation: "setCategory", active: nil,
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
        onEvent?(.sessionOperation(operation: "setActive", active: active,
                                   category: session.category, mode: session.mode,
                                   categoryOptions: categoryOptionNames(session.categoryOptions),
                                   activeOptions: activeOptionNames(options),
                                   isOtherAudioPlaying: session.isOtherAudioPlaying,
                                   secondaryAudioShouldBeSilenced: session.secondaryAudioShouldBeSilenced))
        try session.setActive(active, options: options)
    }

    private func observe(_ name: Notification.Name, handler: @escaping @MainActor (Notification) -> Void) {
        // The system posts these from the shared AVAudioSession, never from the injected `session` wrapper.
        observers.append(NotificationCenter.default.addObserver(forName: name, object: AVAudioSession.sharedInstance(),
                                                                queue: .main) { notification in
            MainActor.assumeIsolated { handler(notification) }
        })
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

private enum AudioSessionActivationError: Error {
    case failed
}
