import Foundation

enum AudioSessionEvent: Equatable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case mediaServicesReset
    /// Headphones or another input/output device appeared or went away.
    case routeChanged
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
