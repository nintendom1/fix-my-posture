import SwiftUI

/// Developer diagnostics: turn workout recordings on or off, and share, copy, or delete them.
struct WorkoutRecordingsScreen: View {
    @Bindable var viewModel: WorkoutRecordingsViewModel
    @State private var deleting: WorkoutRecordingSummary?
    @State private var confirmingDeleteUnmarked = false

    private let recordRed = Color(hex: 0xFF9AA6)
    private var palette: ColorPalette { ColorTokens.palette() }

    var body: some View {
        SettingsSubpage(title: "Workout recordings") {
            card {
                SettingsRow(icon: "videocam", title: "Record workouts", iconColor: recordRed,
                            toggle: $viewModel.isRecordingEnabled)
            }
            Text("Saves each workout's joint positions, rep counting, and coach events on this iPhone, never camera "
                + "images, for up to 60 minutes per workout (about 1 MB a minute). Applies to the next workout. Tap REC "
                + "during a workout to mark a moment. Copy report copies a short text report of tracking losses and "
                + "markers to paste into a chat. The newest 20 recordings are kept; older ones without markers are "
                + "removed first. Pull them to a Mac with `make diagnostics`.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineSpacing(2)
                .foregroundStyle(palette.textSubtle)
                .padding(.horizontal, 4)

            if viewModel.recordings.isEmpty {
                Text("No recordings yet.")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(palette.backgroundCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                Text("\(viewModel.recordings.count) recordings · "
                    + WorkoutRecordingsViewModel.byteLabel(viewModel.totalBytes))
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .tracking(0.85)
                    .textCase(.uppercase)
                    .foregroundStyle(palette.textMuted)
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
                ForEach(viewModel.recordings) { recording in
                    row(recording)
                }
                if viewModel.unmarkedCount > 0 {
                    Button("Delete recordings without markers") { confirmingDeleteUnmarked = true }
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(palette.danger)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(palette.backgroundCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .onAppear(perform: viewModel.refresh)
        .confirmationDialog("Delete this recording?", isPresented: Binding(get: { deleting != nil },
                                                                         set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { recording in
            Button("Delete", role: .destructive) { viewModel.delete(recording.id) }
        }
        .confirmationDialog("Delete \(viewModel.unmarkedCount) recordings without markers?",
                            isPresented: $confirmingDeleteUnmarked, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: viewModel.deleteUnmarked)
        }
    }

    private func row(_ recording: WorkoutRecordingSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(recording.title)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                Text(details(recording))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.textMuted)
            }
            HStack(spacing: 8) {
                ShareLink(item: viewModel.shareURL(for: recording.id)) {
                    actionLabel("Share", icon: "ios_share")
                }
                Button { Task { await viewModel.copyReport(of: recording.id) } } label: {
                    actionLabel(copyTitle(recording.id), icon: viewModel.copiedID == recording.id ? "check" : "content_copy")
                }
                .disabled(viewModel.copyingID != nil)
                Spacer(minLength: 0)
                Button { deleting = recording } label: {
                    Image(material: "delete")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(palette.danger)
                        .frame(width: 40, height: 36)
                }
                .accessibilityLabel("Delete recording")
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.backgroundCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func details(_ recording: WorkoutRecordingSummary) -> String {
        var parts = [WorkoutRecordingsViewModel.dateLabel(recording.startedAt)]
        if let endedAt = recording.endedAt {
            parts.append(WorkoutRecordingHUD.clockLabel(endedAt.timeIntervalSince(recording.startedAt)))
        }
        if recording.markerCount > 0 {
            parts.append("\(recording.markerCount) marker\(recording.markerCount == 1 ? "" : "s")")
        }
        parts.append(WorkoutRecordingsViewModel.byteLabel(recording.byteCount))
        if !recording.isComplete { parts.append("incomplete") }
        return parts.joined(separator: " · ")
    }

    private func copyTitle(_ id: UUID) -> String {
        if viewModel.copyingID == id { return "Copying…" }
        return viewModel.copiedID == id ? "Copied" : "Copy report"
    }

    private func actionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(material: icon)
                .font(.system(size: 13, weight: .bold))
            Text(title)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(palette.tabActive)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color.white.opacity(0.08), in: Capsule())
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0, content: content)
            .background(palette.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
