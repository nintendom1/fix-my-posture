import Foundation

enum AudioSessionEvent: Equatable {
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
    func stopListening()
    func beginDucking()
    func endDucking()
    func deactivate()
}
