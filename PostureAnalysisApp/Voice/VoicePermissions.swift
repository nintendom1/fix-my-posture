import AVFoundation
import Speech

enum VoicePermissionStatus: Equatable {
    case notDetermined
    case granted
    case denied
}

/// Microphone and speech-recognition authorization, requested in that order after the camera.
@MainActor
protocol VoicePermissionProviding {
    var microphone: VoicePermissionStatus { get }
    var speechRecognition: VoicePermissionStatus { get }
    func requestMicrophone(_ completion: @escaping @MainActor (Bool) -> Void)
    func requestSpeechRecognition(_ completion: @escaping @MainActor (Bool) -> Void)
}

@MainActor
struct SystemVoicePermissions: VoicePermissionProviding {
    var microphone: VoicePermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .notDetermined
        }
    }

    var speechRecognition: VoicePermissionStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    func requestMicrophone(_ completion: @escaping @MainActor (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor in completion(granted) }
        }
    }

    func requestSpeechRecognition(_ completion: @escaping @MainActor (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in completion(status == .authorized) }
        }
    }
}
