import Foundation

enum AudioSessionEvent: Equatable, Sendable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    /// Recording-only details; the plain interruption cases above keep their existing workout behavior.
    case interruptionDiagnostic(type: String, reason: Int?, wasSuspended: Bool, shouldResume: Bool?)
    case mediaServicesReset
    /// Headphones or another input/output device appeared or went away.
    case routeChanged
    /// Every route notification, including category changes that do not reconfigure speech input.
    case routeDiagnostic(reason: Int, outputs: [String], inputs: [String])
    /// Audio-session call state captured immediately before a category or activation operation.
    case sessionOperation(operation: String, active: Bool?, category: String, mode: String,
                          categoryOptions: [String], activeOptions: [String],
                          isOtherAudioPlaying: Bool, secondaryAudioShouldBeSilenced: Bool)
    /// A delayed restore re-activated the session for listening.
    case reactivated
}

@MainActor
protocol AudioSessionControlling: AnyObject {
    var onEvent: ((AudioSessionEvent) -> Void)? { get set }
    func configureBaseCategory()
    func setRecordingEnabled(_ enabled: Bool)
    func activateForListening() -> Bool
    func activateForListening(completion: @escaping @MainActor (Bool) -> Void)
    func stopListening()
    func beginDucking()
    func beginDucking(completion: @escaping @MainActor () -> Void)
    func endDucking()
    func endDucking(completion: @escaping @MainActor () -> Void)
    func deactivate()
}

extension AudioSessionControlling {
    /// Synchronous test and adapter implementations can keep their existing behavior.
    func activateForListening(completion: @escaping @MainActor (Bool) -> Void) {
        completion(activateForListening())
    }

    func beginDucking(completion: @escaping @MainActor () -> Void) {
        beginDucking()
        completion()
    }

    func endDucking(completion: @escaping @MainActor () -> Void) {
        endDucking()
        completion()
    }
}
