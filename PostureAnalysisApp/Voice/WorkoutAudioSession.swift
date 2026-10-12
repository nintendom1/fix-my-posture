import AVFoundation
import Foundation

/// Owns the shared audio session during a workout. Other audio keeps playing and is
/// lowered only while the coach speaks.
@MainActor
final class WorkoutAudioSession {
    enum Event {
        case interruptionBegan
        case interruptionEnded(shouldResume: Bool)
        case mediaServicesReset
    }

    private let session = AVAudioSession.sharedInstance()
    private var observers: [NSObjectProtocol] = []
    private(set) var isDucking = false
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
                self.onEvent?(.interruptionBegan)
            case .ended:
                let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
                self.onEvent?(.interruptionEnded(shouldResume: shouldResume))
            @unknown default:
                break
            }
        }
        observe(AVAudioSession.mediaServicesWereResetNotification) { [weak self] _ in
            guard let self else { return }
            self.isDucking = false
            self.configureBaseCategory()
            self.onEvent?(.mediaServicesReset)
        }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private var category: AVAudioSession.Category { .playback }
    private var baseOptions: AVAudioSession.CategoryOptions { [.mixWithOthers] }

    /// Sets the non-ducking category without activating, so nothing is interrupted.
    func configureBaseCategory() {
        try? session.setCategory(category, mode: .default, options: baseOptions)
    }

    /// Lowers other audio. Speech still plays if this fails.
    func beginDucking() {
        guard !isDucking else { return }
        restoreAttempt = 0
        do {
            try session.setCategory(category, mode: .default, options: baseOptions.union(.duckOthers))
            // Marked before activation so endDucking always restores the category.
            isDucking = true
            try session.setActive(true)
        } catch {
            endDucking()
        }
    }

    /// Restores other audio. Idempotent; safe from every completion, error, and teardown path.
    func endDucking() {
        guard isDucking else { return }
        isDucking = false
        restoreAttempt = 0
        restoreOtherAudio()
    }

    private func restoreOtherAudio() {
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            configureBaseCategory()
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
        endDucking()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func observe(_ name: Notification.Name, handler: @escaping @MainActor (Notification) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: .main) { notification in
            MainActor.assumeIsolated { handler(notification) }
        })
    }
}
