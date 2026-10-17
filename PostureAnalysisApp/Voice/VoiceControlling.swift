import Foundation

enum VoiceStatus: Equatable {
    case off
    case requestingPermission
    case needsPermission
    case listening
    case coachSpeaking
    case paused
    /// The user turned the microphone off.
    case muted
    case unavailable(String)

    /// Voice commands work now or will resume on their own.
    var isUsable: Bool {
        switch self {
        case .listening, .coachSpeaking, .paused: return true
        default: return false
        }
    }
}

@MainActor
protocol VoiceControlling: AnyObject {
    var status: VoiceStatus { get }
    var onStatusChanged: ((VoiceStatus) -> Void)? { get set }
    var onCommand: ((WorkoutCommand) -> Void)? { get set }
    var onHeard: ((String) -> Void)? { get set }
    func enable()
    func disable(status: VoiceStatus)
    func setMuted(_ muted: Bool)
    func retry()
    func setCoachSpeaking(_ speaking: Bool)
    func handleAudioEvent(_ event: AudioSessionEvent)
}
