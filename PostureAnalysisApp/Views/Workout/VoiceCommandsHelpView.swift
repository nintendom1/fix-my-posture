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
    let onOpenSettings: () -> Void
    let onDone: () -> Void

    @ScaledMetric(relativeTo: .title2) private var chipMinWidth: CGFloat = 150

    private var palette: ColorPalette { ColorTokens.palette() }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.backgroundPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
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
                            .textStyle(.body)
                            .foregroundStyle(palette.textMuted)
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Voice Commands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .tint(palette.tabActive)
                        .accessibilityIdentifier("voiceCommandsDoneButton")
                }
            }
        }
        .tint(palette.tabActive)
        .environment(\.colorScheme, .dark)
    }

    private var statusHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: VoiceStatusPresentation.symbol(for: micStatus))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(headerColor)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                Text(VoiceStatusPresentation.label(for: micStatus))
                    .textStyle(.headline)
                    .foregroundStyle(palette.textPrimary)
                if let progressLine {
                    Text(progressLine)
                        .textStyle(.body)
                        .monospacedDigit()
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The HUD's light-on-dark colors adjusted for the sheet background.
    private var headerColor: Color {
        switch micStatus {
        case .muted: return palette.danger
        case .coachSpeaking: return palette.textMuted
        default: return VoiceStatusPresentation.color(for: micStatus)
        }
    }

    private var soundToggles: some View {
        VStack(spacing: 4) {
            Toggle(isOn: Binding(get: { !isMicMuted }, set: { onSetMicMuted(!$0) })) {
                Label("Voice commands", systemImage: "mic")
                    .textStyle(.body)
                    .foregroundStyle(palette.textPrimary)
            }
            Toggle(isOn: Binding(get: { !isCoachMuted }, set: { onSetCoachMuted(!$0) })) {
                Label("Coach voice", systemImage: "speaker.wave.2")
                    .textStyle(.body)
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(14)
        .tint(palette.tabActive)
        .background(palette.backgroundCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(palette.borderCard, lineWidth: 1))
    }

    /// Recovery for permission, failure, and pauses; nil while voice is working.
    private var banner: AnyView? {
        let message: String
        let button: (title: String, action: () -> Void)
        switch micStatus {
        case .needsPermission:
            message = "Voice commands need microphone and speech recognition access. Speech is recognized on this iPhone and never recorded."
            button = ("Open Settings", onOpenSettings)
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
                    .textStyle(.body)
                    .foregroundStyle(palette.textPrimary)
                Button(button.title, action: button.action)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(palette.warning)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(palette.warning.opacity(0.2), lineWidth: 1))
        )
    }

    private var rightNow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Right now")
                .textStyle(.eyebrow)
                .foregroundStyle(palette.textMuted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: chipMinWidth), spacing: 10, alignment: .leading)],
                      alignment: .leading, spacing: 10) {
                ForEach(suggestions) { entry in
                    Text("\u{201C}\(entry.title)\u{201D}")
                        .textStyle(.title2)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(palette.brand.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(palette.tabActive.opacity(0.2), lineWidth: 1))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Right now, you can say " + suggestions.map(\.title).joined(separator: ", "))
    }

    private func sectionView(_ section: VoiceCommandHelp.Section) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(section.title)
                .textStyle(.eyebrow)
                .foregroundStyle(palette.textMuted)
            VStack(spacing: 8) {
              ForEach(section.entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\u{201C}\(entry.title)\u{201D}")
                        .textStyle(.title2)
                        .foregroundStyle(palette.textPrimary)
                    Text(entry.detail)
                        .textStyle(.body)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !entry.alternates.isEmpty {
                        Text("Also: " + entry.alternates.map { "\u{201C}\($0)\u{201D}" }.joined(separator: ", "))
                            .textStyle(.caption1)
                            .foregroundStyle(palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if entry.isDestructive {
                        Label("Say it on its own", systemImage: "exclamationmark.bubble")
                            .textStyle(.caption1)
                            .foregroundStyle(palette.warning)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.backgroundCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(palette.borderCard, lineWidth: 1))
                .accessibilityElement(children: .combine)
              }
            }
        }
    }
}
