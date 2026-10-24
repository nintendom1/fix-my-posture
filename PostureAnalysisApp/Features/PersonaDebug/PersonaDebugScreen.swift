import SwiftUI

/// Settings → Developer diagnostics → Persona debug.
struct PersonaDebugScreen: View {
    @Bindable var viewModel: PersonaDebugViewModel
    @State private var isResetConfirmationPresented = false

    var body: some View {
        SettingsSubpage(title: "Persona debug") {
            statusCard
            sentSection
            suppressedSection
            previewSection
        }
        .task { viewModel.refresh() }
        .sheet(item: $viewModel.selectedTrace) { trace in
            PersonaDecisionTraceDetailView(
                trace: trace,
                otherCandidates: viewModel.otherCandidates(for: trace),
                viewModel: viewModel
            )
        }
        .alert("Reset Persona?", isPresented: $isResetConfirmationPresented) {
            Button("Reset", role: .destructive) {
                Task { await viewModel.resetPersona() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("She’ll get to know you again from scratch. Your workouts, assessments, and settings stay.")
        }
    }

    private var statusCard: some View {
        debugCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Persona status")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().textPrimary)

                statusLine(
                    "Extra Personable",
                    value: viewModel.status.extraPersonableEnabled ? "On" : "Off"
                )
                statusLine("Availability", value: availabilityLabel)
                statusLine("Familiarity", value: familiarityLabel(viewModel.status.familiarity))
                statusLine("Trajectory", value: trajectoryLabel(viewModel.status.trajectory))
                statusLine("Cooling", value: coolingLabel(viewModel.status.cooling))
                statusLine(
                    "Standalone today",
                    value: "\(viewModel.status.standaloneCountToday) / \(viewModel.status.dailyCap)"
                )
                statusLine(
                    "Quiet hours",
                    value: "\(viewModel.status.quietHoursSummary) · \(viewModel.status.isQuietNow ? "quiet now" : "not quiet now")"
                )
                statusLine("Pending", value: "\(viewModel.status.pendingCount)")
                if let resetDate = viewModel.status.personaResetDate {
                    statusLine("Reset date", value: viewModel.resetDateLabel(resetDate))
                }

                HStack(spacing: 12) {
                    Button("Run detectors now") {
                        Task { await viewModel.runDetectorsNow() }
                    }
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().tabActive)
                    .accessibilityIdentifier("personaDebugRunDetectors")

                    Spacer(minLength: 4)

                    Button("Reset Persona…") {
                        isResetConfirmationPresented = true
                    }
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().danger)
                    .accessibilityIdentifier("personaDebugReset")
                }
                .padding(.top, 4)
            }
        }
        .accessibilityIdentifier("personaDebugStatus")
    }

    private var availabilityLabel: String {
        if viewModel.loadError != nil { return "Content unavailable" }
        if viewModel.status.isActive { return "Active" }
        return viewModel.status.extraPersonableEnabled ? "Reminders off or Plain style" : "Inactive"
    }

    private var sentSection: some View {
        section(title: "Last 10 sent") {
            if viewModel.sent.isEmpty {
                emptyMessage("No persona notifications have been sent.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.sent.enumerated()), id: \.element.id) { index, trace in
                        Button {
                            viewModel.selectTrace(trace)
                        } label: {
                            sentRow(trace)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(trace.title ?? trace.observation.contentKey), \(PersonaDebugViewModel.deliveryDescription(trace.delivery))")
                        if index < viewModel.sent.count - 1 { rowDivider }
                    }
                }
            }
        }
        .accessibilityIdentifier("personaDebugSent")
    }

    private var suppressedSection: some View {
        section(title: "Recently suppressed") {
            if viewModel.suppressed.isEmpty {
                emptyMessage("No recently suppressed observations.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.suppressed.enumerated()), id: \.element.id) { index, trace in
                        Button {
                            viewModel.selectTrace(trace)
                        } label: {
                            suppressedRow(trace)
                        }
                        .buttonStyle(.plain)
                        if index < viewModel.suppressed.count - 1 { rowDivider }
                    }
                }
            }
        }
        .accessibilityIdentifier("personaDebugSuppressed")
    }

    private var previewSection: some View {
        section(title: "Content preview") {
            VStack(alignment: .leading, spacing: 14) {
                if viewModel.contentKeys.isEmpty {
                    emptyMessage(viewModel.loadError ?? "No persona content is available.")
                } else {
                    contentKeyPicker
                    tonePicker
                    familiarityPicker
                    Toggle("Intro", isOn: $viewModel.intro)
                        .tint(ColorTokens.palette().brand)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .accessibilityIdentifier("personaDebugIntroToggle")
                    variantStepper
                }

                if let preview = viewModel.preview {
                    previewCard(preview)
                } else if !viewModel.contentKeys.isEmpty {
                    emptyMessage("No copy is available for these selections.")
                }

                Button {
                    Task { await viewModel.send() }
                } label: {
                    Text(viewModel.isSending ? "Scheduling…" : "Send")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            ColorTokens.palette().brand.opacity(viewModel.isSending ? 0.55 : 1),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSending || viewModel.preview == nil)
                .accessibilityIdentifier("personaDebugSend")

                sendStatus
            }
        }
        .accessibilityIdentifier("personaDebugPreview")
    }

    private var contentKeyPicker: some View {
        Picker("Content key", selection: Binding(
            get: { viewModel.selectedContentKey ?? "" },
            set: { viewModel.selectContentKey($0) }
        )) {
            ForEach(viewModel.contentKeys, id: \.self) { key in
                Text(key).tag(key)
            }
        }
        .pickerStyle(.menu)
        .tint(ColorTokens.palette().tabActive)
        .accessibilityIdentifier("personaDebugContentKeyPicker")
    }

    private var tonePicker: some View {
        Picker("Tone", selection: $viewModel.tone) {
            ForEach(PersonaTone.allCases, id: \.self) { tone in
                Text(toneLabel(tone)).tag(tone)
            }
        }
        .pickerStyle(.menu)
        .tint(ColorTokens.palette().tabActive)
        .accessibilityIdentifier("personaDebugTonePicker")
    }

    private var familiarityPicker: some View {
        Picker("Familiarity", selection: $viewModel.familiarity) {
            ForEach(PersonaFamiliarity.allCases, id: \.self) { familiarity in
                Text(familiarityLabel(familiarity)).tag(familiarity)
            }
        }
        .pickerStyle(.menu)
        .tint(ColorTokens.palette().tabActive)
        .accessibilityIdentifier("personaDebugFamiliarityPicker")
    }

    private var variantStepper: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.stepVariant(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(ColorTokens.palette().tabActive)
                    .frame(width: 42, height: 36)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous variant")

            Text("Variant \(viewModel.variantIndex + 1) of \(viewModel.variantCount)")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textMuted)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("personaDebugVariant")

            Button {
                viewModel.stepVariant(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(ColorTokens.palette().tabActive)
                    .frame(width: 42, height: 36)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next variant")
        }
    }

    private func previewCard(_ preview: PersonaComposition) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(preview.content.title)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().textPrimary)
                Text(preview.content.body)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Art: \(preview.content.artLabel)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().textSubtle)
                Text("Template ID: \(preview.templateID)")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(ColorTokens.palette().textSubtle)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(preview.content.imageAssetName)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var sendStatus: some View {
        switch viewModel.sendState {
        case .idle, .sending:
            EmptyView()
        case .sent:
            statusMessage("Preview scheduled.")
        case .failed(let message):
            statusMessage(message)
        }
    }

    private func sentRow(_ trace: PersonaDecisionTrace) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(viewModel.shortTime(for: trace.fireDate ?? trace.decidedAt))
                    Spacer(minLength: 8)
                    Text(viewModel.sentRowLabel(trace))
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textSubtle)

                Text(trace.title ?? trace.observation.contentKey)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().textPrimary)
                    .multilineTextAlignment(.leading)
                Text("\(trace.family.rawValue.capitalized) · \(trace.salience.rawValue.uppercased())")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().textMuted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ColorTokens.palette().textSubtle)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func suppressedRow(_ trace: PersonaDecisionTrace) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(trace.family.rawValue).\(trace.observation.key.kind)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().textPrimary)
                Spacer(minLength: 8)
                Text(viewModel.shortTime(for: trace.decidedAt))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().textSubtle)
            }
            Text(trace.suppressionReason.map(PersonaDebugViewModel.suppressionDescription) ?? "No suppression reason")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textMuted)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 13, weight: .black, design: .rounded))
                .tracking(0.85)
                .foregroundStyle(ColorTokens.palette().textMuted)
                .padding(.horizontal, 4)
            debugCard(content: content)
        }
        .padding(.top, 6)
    }

    private func debugCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ColorTokens.palette().backgroundCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func statusLine(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(ColorTokens.palette().textMuted)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
    }

    private var rowDivider: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
    }

    private func emptyMessage(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(ColorTokens.palette().textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusMessage(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(ColorTokens.palette().textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func familiarityLabel(_ familiarity: PersonaFamiliarity) -> String {
        switch familiarity {
        case .new: "New"
        case .familiar: "Familiar"
        case .established: "Established"
        case .longTerm: "Long term"
        }
    }

    private func toneLabel(_ tone: PersonaTone) -> String {
        tone.rawValue.capitalized
    }

    private func trajectoryLabel(_ trajectory: PersonaTrajectory) -> String {
        trajectory.rawValue.capitalized
    }

    private func coolingLabel(_ cooling: PersonaCoolingLevel) -> String {
        cooling.rawValue.capitalized
    }
}

private struct PersonaDecisionTraceDetailView: View {
    let trace: PersonaDecisionTrace
    let otherCandidates: [PersonaDecisionTrace]
    let viewModel: PersonaDebugViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AuraBackground(tab: .train)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        detailCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(trace.title ?? trace.observation.contentKey)
                                    .font(.system(size: 20, weight: .black, design: .rounded))
                                    .foregroundStyle(ColorTokens.palette().textPrimary)
                                Text(trace.body ?? "No body copy recorded.")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(ColorTokens.palette().textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        detailCard {
                            VStack(alignment: .leading, spacing: 8) {
                                detailLine("Family", value: trace.family.rawValue.capitalized)
                                detailLine("Salience", value: trace.salience.rawValue.uppercased())
                                detailLine("Delivery", value: PersonaDebugViewModel.deliveryDescription(trace.delivery))
                                detailLine("Observation key", value: trace.observation.key.string)
                                detailLine("Familiarity", value: familiarityLabel(trace.familiarity))
                                detailLine("Trajectory", value: trace.trajectory.rawValue.capitalized)
                                detailLine("Tone", value: trace.tone.map { $0.rawValue.capitalized } ?? "None")
                                detailLine("Template ID", value: trace.templateID ?? "None")
                                detailLine(
                                    "Standalone count that day",
                                    value: "\(trace.standaloneCountToday) / \(PersonaPolicy.standard.dailyStandaloneCap)"
                                )
                                detailLine("Cooling", value: trace.cooling.rawValue.capitalized)
                                detailLine("Quiet/deferred", value: trace.quietDeferred ? "Yes" : "No")
                                detailLine("Recent similar count", value: "\(trace.recentSimilarCount)")
                                detailLine(
                                    "Suppression reason",
                                    value: trace.suppressionReason.map(PersonaDebugViewModel.suppressionDescription) ?? "None"
                                )
                            }
                        }

                        detailCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Evidence")
                                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                                    .foregroundStyle(ColorTokens.palette().textPrimary)
                                ForEach(Array(trace.observation.evidence.lines.enumerated()), id: \.offset) { _, line in
                                    Text("• \(line)")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(ColorTokens.palette().textMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }

                        detailCard {
                            VStack(spacing: 8) {
                                meterRow(
                                    "Familiarity",
                                    dots: PersonaDebugMeters.familiarityDots(trace.familiarity),
                                    value: familiarityLabel(trace.familiarity)
                                )
                                meterRow(
                                    "Trajectory",
                                    dots: PersonaDebugMeters.trajectoryDots(trace.trajectory),
                                    value: trace.trajectory.rawValue.capitalized
                                )
                                meterRow(
                                    "Evidence",
                                    dots: PersonaDebugMeters.evidenceDots(strength: trace.observation.evidence.strength),
                                    value: "\(trace.observation.evidence.strength) / 5"
                                )
                                meterRow(
                                    "Repetition risk",
                                    dots: PersonaDebugMeters.repetitionRiskDots(recentSimilarCount: trace.recentSimilarCount),
                                    value: "\(trace.recentSimilarCount)"
                                )
                                meterRow(
                                    "Cooling",
                                    dots: PersonaDebugMeters.coolingDots(trace.cooling),
                                    value: trace.cooling.rawValue.capitalized
                                )
                                Text("Salience \(trace.salience.rawValue.uppercased())")
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundStyle(ColorTokens.palette().textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 2)
                            }
                        }

                        detailCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Other candidates considered")
                                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                                    .foregroundStyle(ColorTokens.palette().textPrimary)
                                if otherCandidates.isEmpty {
                                    detailLine("Candidates", value: "None")
                                } else {
                                    ForEach(otherCandidates) { candidate in
                                        detailLine(
                                            candidate.observation.key.string,
                                            value: "\(candidate.salience.rawValue.uppercased()) · \(candidate.suppressionReason.map(PersonaDebugViewModel.suppressionDescription) ?? PersonaDebugViewModel.deliveryDescription(candidate.delivery))"
                                        )
                                    }
                                }
                                Text("Why: \(trace.whyThisWon)")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(ColorTokens.palette().textMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Persona decision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                }
            }
        }
    }

    private func detailCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ColorTokens.palette().backgroundCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func detailLine(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(ColorTokens.palette().textMuted)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
    }

    private func meterRow(_ title: String, dots: Int, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(meterText(dots))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(ColorTokens.palette().tabActive)
                .accessibilityLabel("\(dots) of 4")
            Text(value)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .frame(minWidth: 68, alignment: .trailing)
        }
    }

    private func meterText(_ dots: Int) -> String {
        let filled = min(4, max(0, dots))
        return String(repeating: "●", count: filled) + String(repeating: "○", count: 4 - filled)
    }

    private func familiarityLabel(_ familiarity: PersonaFamiliarity) -> String {
        switch familiarity {
        case .new: "New"
        case .familiar: "Familiar"
        case .established: "Established"
        case .longTerm: "Long term"
        }
    }
}
