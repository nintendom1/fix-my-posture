import SwiftUI

/// Developer page: pick any character notification, set a delay, and send it to this iPhone.
struct NotificationPreviewScreen: View {
    @Bindable var viewModel: NotificationPreviewViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        SettingsSubpage(title: "Notification preview") {
            if let loadError = viewModel.loadError {
                card { bodyText(loadError) }
            } else {
                previewCard
                controlsCard
                if viewModel.hasDiagnostics { diagnosticsCard }
                Text(explanation)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().textSubtle)
                    .padding(.horizontal, 4)
                scenarioGroup(title: "Reminders", kind: .nudge)
                scenarioGroup(title: "After a workout", kind: .acknowledgment)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.loadError == nil { sendBar }
        }
        .task {
            await viewModel.refreshAuthorization()
            await viewModel.refreshDiagnostics()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await viewModel.refreshAuthorization()
                await viewModel.refreshDiagnostics()
            }
        }
    }

    private var explanation: String {
        "After you tap Send, lock your phone or press Home to see it as a real notification. "
            + "Reminders only appear when the app isn't open. Post-workout messages also appear while it is."
    }

    // MARK: Preview

    private var previewCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                if let preview = viewModel.preview {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preview.title)
                                .font(.system(size: 16, weight: .heavy, design: .rounded))
                                .foregroundStyle(ColorTokens.palette().textPrimary)
                                .accessibilityIdentifier("notificationPreviewTitle")
                            Text(preview.body)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(ColorTokens.palette().textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("notificationPreviewBody")
                        }
                        Spacer(minLength: 8)
                        Image(preview.imageAssetName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityHidden(true)
                    }
                    Text("\(preview.artLabel) · \(viewModel.selectedScenario?.kind.rawValue ?? "")")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textSubtle)
                }
                variantRow
            }
        }
    }

    private var variantRow: some View {
        HStack(spacing: 12) {
            stepButton(systemName: "chevron.left", label: "Previous variant") { viewModel.stepVariant(by: -1) }
            Text("Variant \(viewModel.variantIndex + 1) of \(max(viewModel.variantCount, 1))")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textMuted)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("notificationPreviewVariant")
            stepButton(systemName: "chevron.right", label: "Next variant") { viewModel.stepVariant(by: 1) }
        }
    }

    private func stepButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(ColorTokens.palette().tabActive)
                .frame(width: 44, height: 36)
                .background(Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Delay

    private var controlsCard: some View {
        card {
            Stepper(value: $viewModel.delaySeconds, in: NotificationPreviewDelay.range) {
                HStack {
                    Text("Delay")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textPrimary)
                    Spacer(minLength: 8)
                    Text("\(viewModel.delaySeconds) s")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textMuted)
                        .accessibilityIdentifier("notificationPreviewDelayValue")
                }
            }
            .accessibilityIdentifier("notificationPreviewDelayStepper")
        }
    }

    // MARK: Diagnostics

    private var diagnosticsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("On this iPhone")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textPrimary)
                    Spacer(minLength: 8)
                    Button("Refresh") { Task { await viewModel.refreshDiagnostics() } }
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().tabActive)
                        .accessibilityIdentifier("notificationDiagnosticsRefreshButton")
                }
                if let diagnostics = viewModel.diagnostics {
                    diagnosticsLine(diagnostics.settings.joined(separator: " · "), muted: true)
                    diagnosticsLine(
                        "Reminders queued: \(diagnostics.pendingReminders.count) · "
                            + "Replies or previews queued: \(diagnostics.pending.count - diagnostics.pendingReminders.count) · "
                            + "Delivered: \(diagnostics.delivered.count)"
                    )
                    ForEach(Array(diagnostics.pending.prefix(5).enumerated()), id: \.offset) { _, pending in
                        diagnosticsLine("\(pending.fireDate.map(shortDate) ?? "no date") · \(pending.title)", muted: true)
                    }
                    if diagnostics.pending.count > 5 {
                        diagnosticsLine("and \(diagnostics.pending.count - 5) more", muted: true)
                    }
                    ForEach(Array(diagnostics.recentEvents.suffix(6).enumerated()), id: \.offset) { _, event in
                        Text(event)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(ColorTokens.palette().textSubtle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    diagnosticsLine("Reading…", muted: true)
                }
            }
        }
        .accessibilityIdentifier("notificationDiagnosticsCard")
    }

    private func diagnosticsLine(_ text: String, muted: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(muted ? ColorTokens.palette().textMuted : ColorTokens.palette().textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: Scenarios

    private func scenarioGroup(title: String, kind: NotificationScenario.Kind) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .tracking(0.85)
                .textCase(.uppercase)
                .foregroundStyle(ColorTokens.palette().textMuted)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                let scenarios = viewModel.scenarios(of: kind)
                ForEach(Array(scenarios.enumerated()), id: \.element.id) { index, scenario in
                    scenarioRow(scenario, showsSeparator: index > 0)
                }
            }
            .background(ColorTokens.palette().backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(.top, 8)
    }

    private func scenarioRow(_ scenario: NotificationScenario, showsSeparator: Bool) -> some View {
        let isSelected = viewModel.selectedID == scenario.id
        return Button {
            viewModel.select(scenario.id)
        } label: {
            HStack(spacing: 12) {
                Image(scenario.art[0].assetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(scenario.name)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(scenario.art[0].label)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textSubtle)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(ColorTokens.palette().tabActive)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(isSelected ? Color.white.opacity(0.06) : Color.clear)
            .overlay(alignment: .top) {
                if showsSeparator { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("notificationPreviewScenario.\(scenario.id)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Send

    private var sendBar: some View {
        VStack(spacing: 8) {
            if viewModel.authorization == .denied {
                Button("Open Notification Settings", action: viewModel.openNotificationSettings)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().tabActive)
            }
            Button {
                Task { await viewModel.send() }
            } label: {
                Text(sendTitle)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        ColorTokens.palette().brand.opacity(viewModel.isBusy ? 0.5 : 1),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isBusy || viewModel.preview == nil)
            .accessibilityIdentifier("notificationPreviewSendButton")
            if case .failed(let message) = viewModel.sendState {
                Text(message)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().danger)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(ColorTokens.palette().backgroundPrimary.opacity(0.94))
    }

    private var sendTitle: String {
        switch viewModel.sendState {
        case .idle, .failed:
            "Send in \(viewModel.delaySeconds) s"
        case .countingDown(let seconds):
            "Arriving in \(seconds) s. Lock your phone now"
        case .sent:
            "Sent. Send again"
        }
    }

    // MARK: Pieces

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ColorTokens.palette().backgroundCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(ColorTokens.palette().textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
