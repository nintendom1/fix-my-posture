import SwiftUI

/// Top-bar microphone toggle. The icon is always a microphone: color shows listening, and a red
/// disc shows muted. Tapping mutes or unmutes (or opens help when voice needs fixing); long-press
/// offers Voice Commands.
struct MicrophoneStatusView: View {
    let status: VoiceStatus
    let onTap: () -> Void
    let onShowCommands: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: Self.symbol(for: status))
                .font(.title3)
                .foregroundStyle(Self.color(for: status))
                .frame(width: 32, height: 32)
                .background(status == .muted ? Color.red.opacity(0.85) : Color.black.opacity(0.5))
                .clipShape(Circle())
        }
        .contextMenu {
            Button(action: onShowCommands) {
                Label("Voice Commands", systemImage: "text.bubble")
            }
            if status == .muted {
                Button(action: onTap) { Label("Unmute Microphone", systemImage: "mic") }
            } else if status == .listening || status == .coachSpeaking {
                Button(action: onTap) { Label("Mute Microphone", systemImage: "mic.slash") }
            }
        }
        .accessibilityLabel(Self.label(for: status))
        .accessibilityHint(Self.hint(for: status))
        .accessibilityIdentifier("workoutMicrophoneButton")
    }

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
        // Still a microphone, just dimmed: listening resumes when the coach finishes.
        case .coachSpeaking: return .white.opacity(0.45)
        case .muted: return .white
        case .needsPermission, .unavailable: return .orange
        case .paused, .off, .requestingPermission: return .gray
        }
    }

    /// The current state, for the help header and VoiceOver.
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

    static func hint(for status: VoiceStatus) -> String {
        switch status {
        case .listening, .coachSpeaking: return "Mutes the microphone. Touch and hold for voice commands."
        case .muted: return "Turns the microphone back on."
        case .paused, .off: return "Tries to listen again."
        case .needsPermission, .unavailable: return "Shows voice commands and how to fix this."
        case .requestingPermission: return ""
        }
    }
}

/// Top-bar coach-voice toggle: one tap silences or restores the coach.
struct CoachVoiceButton: View {
    let isMuted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(isMuted ? Color.red.opacity(0.85) : Color.black.opacity(0.5))
                .clipShape(Circle())
        }
        .accessibilityLabel(isMuted ? "Coach voice muted" : "Coach voice on")
        .accessibilityHint(isMuted ? "Turns the coach's voice back on." : "Silences the coach.")
        .accessibilityIdentifier("workoutCoachVoiceButton")
    }
}
