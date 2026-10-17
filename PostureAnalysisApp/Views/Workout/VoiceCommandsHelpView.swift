import SwiftUI
import UIKit

/// Every voice command, readable from across the room. Opens by voice ("what can I say") or by
/// touch, and closes by voice ("close"). The workout keeps running behind it.
struct VoiceCommandsHelpView: View {
    let sections: [VoiceCommandHelp.Section]
    /// Commands that make sense right now.
    let suggestions: [VoiceCommandHelp.Entry]
    let micStatus: VoiceStatus
    let isMicMuted: Bool
    let isCoachMuted: Bool
    let onSetMicMuted: (Bool) -> Void
    let onSetCoachMuted: (Bool) -> Void
    /// Live progress, since counting continues while this is open.
    let progressLine: String?
    let onRetry: () -> Void
    let onDone: () -> Void

    @ScaledMetric(relativeTo: .title2) private var chipMinWidth: CGFloat = 150

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    statusHeader
                    soundToggles
                    if let banner {
                        banner
                    }
                    if !suggestions.isEmpty {
                        rightNow
                    }
                    ForEach(sections) { section in
                        sectionView(section)
                    }
                    Text("The coach doesn't listen while it's speaking. Say \u{201C}close\u{201D} to go back.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("Voice Commands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                        .accessibilityIdentifier("voiceCommandsDoneButton")
                }
            }
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: MicrophoneStatusView.symbol(for: micStatus))
                .font(.title2)
                .foregroundStyle(headerColor)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.secondary.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(MicrophoneStatusView.label(for: micStatus))
                    .font(.headline)
                if let progressLine {
                    Text(progressLine)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The HUD's light-on-dark colors adjusted for the sheet background.
    private var headerColor: Color {
        switch micStatus {
        case .muted: return .red
        case .coachSpeaking: return .secondary
        default: return MicrophoneStatusView.color(for: micStatus)
        }
    }

    private var soundToggles: some View {
        VStack(spacing: 4) {
            Toggle(isOn: Binding(get: { !isMicMuted }, set: { onSetMicMuted(!$0) })) {
                Label("Voice commands", systemImage: "mic")
                    .font(.title3)
            }
            Toggle(isOn: Binding(get: { !isCoachMuted }, set: { onSetCoachMuted(!$0) })) {
                Label("Coach voice", systemImage: "speaker.wave.2")
                    .font(.title3)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.1)))
    }

    /// Recovery for permission, failure, and pauses; nil while voice is working.
    private var banner: AnyView? {
        let message: String
        let button: (title: String, action: () -> Void)
        switch micStatus {
        case .needsPermission:
            message = "Voice commands need microphone and speech recognition access. Speech is recognized on this iPhone and never recorded."
            button = ("Open Settings", {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            })
        case .unavailable(let reason):
            message = reason + " The buttons still work."
            button = ("Try Again", onRetry)
        case .paused, .off:
            message = "Listening is paused, for example after a call. The buttons still work."
            button = ("Try Again", onRetry)
        case .muted:
            message = "The microphone is muted, so voice commands are off. The buttons still work."
            button = ("Unmute Microphone", { onSetMicMuted(false) })
        case .listening, .coachSpeaking, .requestingPermission:
            return nil
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .font(.body)
                Button(button.title, action: button.action)
                    .buttonStyle(.borderedProminent)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.15)))
        )
    }

    private var rightNow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Right now")
                .font(.headline)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: chipMinWidth), spacing: 10, alignment: .leading)],
                      alignment: .leading, spacing: 10) {
                ForEach(suggestions) { entry in
                    Text("\u{201C}\(entry.title)\u{201D}")
                        .font(.title2.bold())
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.15)))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Right now, you can say " + suggestions.map(\.title).joined(separator: ", "))
    }

    private func sectionView(_ section: VoiceCommandHelp.Section) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(section.title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(section.entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\u{201C}\(entry.title)\u{201D}")
                        .font(.title2.bold())
                    Text(entry.detail)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !entry.alternates.isEmpty {
                        Text("Also: " + entry.alternates.map { "\u{201C}\($0)\u{201D}" }.joined(separator: ", "))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if entry.isDestructive {
                        Label("Say it on its own", systemImage: "exclamationmark.bubble")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
