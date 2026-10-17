import AVFoundation
import Foundation

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

    private let session = AVAudioSession.sharedInstance()
    private var observers: [NSObjectProtocol] = []
    private(set) var isDucking = false
    private(set) var isActive = false
    private(set) var isRecordingEnabled = false
    /// Re-activate after speech so the microphone keeps listening.
    private var keepsActive = false
    var onEvent: ((Event) -> Void)?
    private var restoreAttempt = 0

    /// Deactivation can report busy while the synthesizer releases output; retry briefly so other
    /// audio is never left lowered.
    static let restoreRetryDelay: TimeInterval = 0.25
    static let maximumRestoreAttempts = 4

    init() {
        observe(AVAudioSession.interruptionNotification) { [weak self] notification in
            guard let self,
                  let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
            switch type {
            case .began:
                // The system already deactivated the session; just forget the ducked state.
                self.isDucking = false
                self.isActive = false
                self.onEvent?(.interruptionBegan)
            case .ended:
                let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
                self.onEvent?(.interruptionEnded(shouldResume: shouldResume))
            @unknown default:
                break
            }
        }
        observe(AVAudioSession.routeChangeNotification) { [weak self] notification in
            guard let self,
                  let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else { return }
            // Our own category changes also post route changes; only device changes matter here.
            if reason == .newDeviceAvailable || reason == .oldDeviceUnavailable {
                self.onEvent?(.routeChanged)
            }
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
        try? session.setCategory(category, mode: .default, options: baseOptions)
    }

    func setRecordingEnabled(_ enabled: Bool) {
        guard enabled != isRecordingEnabled else { return }
        isRecordingEnabled = enabled
        if !isDucking { configureBaseCategory() }
    }

    /// Activates the recording category for listening. Returns false if the session can't activate.
    func activateForListening() -> Bool {
        keepsActive = true
        guard !isDucking else { return false }
        configureBaseCategory()
        return setActive(true)
    }

    /// Stops keeping the session active for the microphone and releases it unless the coach is speaking.
    func stopListening() {
        keepsActive = false
        guard !isDucking, isActive else { return }
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        isActive = false
    }

    /// Lowers other audio. Listening must already be stopped. Speech still plays if this fails.
    func beginDucking() {
        guard !isDucking else { return }
        restoreAttempt = 0
        // Ducking applies on activation, so an already-active listening session is cycled first.
        if isActive {
            try? session.setActive(false)
            isActive = false
        }
        do {
            try session.setCategory(category, mode: .default, options: baseOptions.union(.duckOthers))
            // Marked before activation so endDucking always restores the category.
            isDucking = true
            try session.setActive(true)
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
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            isActive = false
            configureBaseCategory()
            if keepsActive {
                _ = setActive(true)
                if restoreAttempt > 0 { onEvent?(.reactivated) }
            }
        } catch {
            restoreAttempt += 1
            guard restoreAttempt < Self.maximumRestoreAttempts else {
                configureBaseCategory()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.restoreRetryDelay) { [weak self] in
                MainActor.assumeIsolated {
                    // A new utterance started ducking again; it will restore when it finishes.
                    guard let self, !self.isDucking, self.restoreAttempt > 0 else { return }
                    self.restoreOtherAudio()
                }
            }
        }
    }

    /// Ends ducking and releases the session when leaving the workout.
    func deactivate() {
        keepsActive = false
        endDucking()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        isActive = false
    }

    private func setActive(_ active: Bool) -> Bool {
        do {
            try session.setActive(active)
            isActive = active
            return true
        } catch {
            return false
        }
    }

    private func observe(_ name: Notification.Name, handler: @escaping @MainActor (Notification) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: .main) { notification in
            MainActor.assumeIsolated { handler(notification) }
        })
    }
}
