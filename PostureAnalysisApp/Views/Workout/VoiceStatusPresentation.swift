import SwiftUI

/// Shared labels and colors used by the Voice Commands help sheet.
enum VoiceStatusPresentation {
    static func symbol(for status: VoiceStatus) -> String {
        switch status {
        case .listening, .coachSpeaking: return "mic.fill"
        case .muted, .needsPermission, .unavailable: return "mic.slash.fill"
        case .paused, .off, .requestingPermission: return "mic.slash"
        }
    }

    static func color(for status: VoiceStatus) -> Color {
        switch status {
        case .listening: return WorkoutJointOverlayView.endPositionColor
        case .coachSpeaking: return .white.opacity(0.45)
        case .muted: return .white
        case .needsPermission, .unavailable: return .orange
        case .paused, .off, .requestingPermission: return .gray
        }
    }

    static func label(for status: VoiceStatus) -> String {
        switch status {
        case .listening: return "Listening for voice commands"
        case .coachSpeaking: return "Listening resumes after the coach speaks"
        case .muted: return "Microphone muted"
        case .paused, .off: return "Voice commands paused"
        case .requestingPermission: return "Waiting for microphone permission"
        case .needsPermission: return "Voice commands need microphone and speech permission"
        case .unavailable: return "Voice commands unavailable"
        }
    }
}
