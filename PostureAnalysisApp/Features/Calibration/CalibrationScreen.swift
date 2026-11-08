import AdaptiveTraining
import SwiftUI

/// The first calibration: a short quiz, then tiny samples rated Too Hard / Okay / Easy, then the starting points to
/// accept. It finds a comfortable place to begin; it is never a test. Every step comes from `CalibrationFlow`.
struct CalibrationScreen: View {
    @Bindable var viewModel: CalibrationViewModel
    @Environment(\.workoutCoachFactory) private var coachFactory

    private var palette: ColorPalette { ColorTokens.palette() }

    var body: some View {
        ZStack {
            AuraBackground(tab: .train)
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        content
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
        }
        .task { viewModel.begin() }
        .fullScreenCover(item: sampleBinding) { launch in
            sampleCover(launch)
        }
        .confirmationDialog(CalibrationCopy.leaveTitle, isPresented: confirmingBinding, titleVisibility: .visible) {
            Button(CalibrationCopy.leave, role: .destructive) { viewModel.confirmLeave() }
                .accessibilityIdentifier("calibrationConfirmLeaveButton")
            Button(CalibrationCopy.keepGoing, role: .cancel) { viewModel.keepGoing() }
                .accessibilityIdentifier("calibrationKeepGoingButton")
        } message: {
            Text(CalibrationCopy.leaveDetail)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Bindings

    private var sampleBinding: Binding<CalibrationProbeLaunch?> {
        Binding(get: { viewModel.probeLaunch }, set: { if $0 == nil { viewModel.sampleClosed() } })
    }

    private var confirmingBinding: Binding<Bool> {
        Binding(get: { viewModel.isConfirmingExit }, set: { if !$0 { viewModel.keepGoing() } })
    }

    // MARK: - Layout

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.requestExit()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(palette.backgroundCard, in: Circle())
                    .frame(minWidth: Metrics.Size.tapTarget, minHeight: Metrics.Size.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(CalibrationCopy.close)
            .accessibilityIdentifier("calibrationCloseButton")

            Text(viewModel.title)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.couldNotStart {
            messageCard(CalibrationCopy.couldNotStart, identifier: "calibrationCouldNotStart")
            secondaryButton(CalibrationCopy.close, identifier: "calibrationCloseTextButton") { viewModel.requestExit() }
        } else if let outcome = viewModel.outcome {
            if outcome == .committed {
                doneStep
            } else {
                messageCard(CalibrationCopy.leaveDetail, identifier: "calibrationLeft")
            }
        } else if let step = viewModel.step {
            switch step {
            case .equipment: equipmentStep
            case .families: areasStep
            case .closeness: closenessStep
            case .probe: sampleStep
            case .summary: summaryStep
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    // MARK: - Quiz

    private var equipmentStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            intro
            heading(CalibrationCopy.equipmentTitle)
            detail(CalibrationCopy.equipmentDetail)
            card {
                ForEach(Array(TrainingEquipment.allCases.enumerated()), id: \.element) { index, equipment in
                    choiceRow(title: CalibrationCopy.equipmentName(equipment),
                              isSelected: viewModel.selectedEquipment.contains(equipment),
                              showsSeparator: index < TrainingEquipment.allCases.count - 1,
                              identifier: "calibrationEquipment_\(equipment.rawValue)") {
                        viewModel.toggleEquipment(equipment)
                    }
                }
            }
            primaryButton(CalibrationCopy.continueButton, identifier: "calibrationContinueButton") {
                viewModel.continueFromEquipment()
            }
        }
    }

    private var areasStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            intro
            heading(viewModel.areasTitle)
            detail(viewModel.areasDetail)
            card {
                ForEach(Array(viewModel.offeredFamilies.enumerated()), id: \.element) { index, family in
                    choiceRow(title: CalibrationCopy.areaName(family), detail: CalibrationCopy.areaDetail(family),
                              isSelected: viewModel.selectedFamilies.contains(family),
                              showsSeparator: index < viewModel.offeredFamilies.count - 1,
                              identifier: "calibrationArea_\(family.rawValue)") {
                        viewModel.toggleFamily(family)
                    }
                }
            }
            if !viewModel.canContinueFromAreas {
                detail(CalibrationCopy.areasNeedOne)
            }
            primaryButton(CalibrationCopy.continueButton, isEnabled: viewModel.canContinueFromAreas,
                          identifier: "calibrationContinueButton") {
                viewModel.continueFromAreas()
            }
        }
    }

    private var closenessStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let family = viewModel.closenessArea {
                Text(CalibrationCopy.areaName(family))
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textMuted)
                    .accessibilityIdentifier("calibrationArea")
            }
            heading(CalibrationCopy.closenessTitle)
            detail(CalibrationCopy.closenessNote)
            card {
                ForEach(viewModel.closenessOptions) { option in
                    answerRow(title: option.name, identifier: "calibrationCloseness_\(option.variant.rawValue)") {
                        viewModel.answerCloseness(option.variant)
                    }
                }
                answerRow(title: CalibrationCopy.notSure, detail: CalibrationCopy.notSureDetail,
                          showsSeparator: false, identifier: "calibrationNotSureButton") {
                    viewModel.answerCloseness(nil)
                }
            }
            secondaryButton(CalibrationCopy.skipArea, identifier: "calibrationSkipAreaButton") { viewModel.skipArea() }
        }
    }

    // MARK: - Samples

    @ViewBuilder
    private var sampleStep: some View {
        if let sample = viewModel.sample {
            VStack(alignment: .leading, spacing: 16) {
                Text(sample.area)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textMuted)
                    .accessibilityIdentifier("calibrationArea")
                heading(sample.isHarderOffer ? CalibrationCopy.harderTitle : CalibrationCopy.sampleTitle)
                card {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sample.exercise)
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(palette.textPrimary)
                        Text(sample.amount)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.textSecondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("calibrationSample")
                }
                detail(sample.isHarderOffer ? CalibrationCopy.harderDetail : CalibrationCopy.sampleDetail)
                if let notice = viewModel.notice {
                    Text(notice)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("calibrationNotice")
                }
                if sample.isHarderOffer {
                    primaryButton(CalibrationCopy.tryHarder, identifier: "calibrationTryHarderButton") {
                        viewModel.startSample()
                    }
                    secondaryButton(CalibrationCopy.stayHere, identifier: "calibrationStayHereButton") {
                        viewModel.declineHarderSample()
                    }
                } else {
                    primaryButton(CalibrationCopy.startSample, identifier: "calibrationStartSampleButton") {
                        viewModel.startSample()
                    }
                    secondaryButton(CalibrationCopy.skipArea, identifier: "calibrationSkipAreaButton") {
                        viewModel.skipArea()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sampleCover(_ launch: CalibrationProbeLaunch) -> some View {
        if let coachFactory {
            Self.sampleCoach(model: coachFactory.makeCalibrationProbe(launch))
        } else {
            ZStack {
                Color.black.ignoresSafeArea()
                secondaryButton(CalibrationCopy.close, identifier: "calibrationSampleCloseButton") {
                    viewModel.sampleClosed()
                }
                .padding(20)
            }
        }
    }

    /// The coach for one sample. A sample is a tiny trial of a rung, not a workout, so closing or ending it never writes
    /// to history or tells reminders; its evidence is still recorded.
    static func sampleCoach(model: WorkoutCoachModel) -> WorkoutCoachView {
        WorkoutCoachView(model: model, savesHistory: false)
    }

    // MARK: - Summary

    private var summaryStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading(CalibrationCopy.summaryTitle)
            if viewModel.summaryLines.isEmpty {
                detail(CalibrationCopy.summaryEmpty)
            } else {
                detail(viewModel.summaryDetail)
                card {
                    ForEach(Array(viewModel.summaryLines.enumerated()), id: \.element.id) { index, line in
                        VStack(spacing: 0) {
                            Text(line.text)
                                .font(.system(size: 17, weight: .heavy, design: .rounded))
                                .foregroundStyle(palette.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .accessibilityIdentifier("calibrationSummaryLine_\(line.family.rawValue)")
                            if index < viewModel.summaryLines.count - 1 { separator }
                        }
                    }
                }
            }
            if let notice = viewModel.notice {
                Text(notice)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("calibrationNotice")
            }
            if !viewModel.summaryLines.isEmpty {
                primaryButton(CalibrationCopy.useThese, identifier: "calibrationUseTheseButton") { viewModel.useThese() }
            }
            secondaryButton(CalibrationCopy.leaveWithoutSaving, identifier: "calibrationLeaveButton") {
                viewModel.leave()
            }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading(CalibrationCopy.doneTitle)
            detail(CalibrationCopy.doneDetail)
            card {
                ForEach(Array(viewModel.summaryLines.enumerated()), id: \.element.id) { _, line in
                    Text(line.text)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            }
            primaryButton(CalibrationCopy.done, identifier: "calibrationDoneButton") { viewModel.finish() }
        }
    }

    // MARK: - Pieces

    private var intro: some View {
        Text(viewModel.intro)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("calibrationIntro")
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 24, weight: .heavy, design: .rounded))
            .foregroundStyle(palette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(palette.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func messageCard(_ text: String, identifier: String) -> some View {
        card {
            Text(text)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .accessibilityIdentifier(identifier)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(palette.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var separator: some View {
        Rectangle().fill(palette.borderCard).frame(height: 1).padding(.leading, 16)
    }

    /// A row that can be turned on and off.
    private func choiceRow(title: String, detail: String = "", isSelected: Bool, showsSeparator: Bool,
                           identifier: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    rowText(title: title, detail: detail)
                    Spacer(minLength: 8)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? palette.tabActive : palette.textSubtle)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
            .accessibilityIdentifier(identifier)
            if showsSeparator { separator }
        }
    }

    /// A row that answers a question when tapped.
    private func answerRow(title: String, detail: String = "", showsSeparator: Bool = true, identifier: String,
                           action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    rowText(title: title, detail: detail)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.textSubtle)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(identifier)
            if showsSeparator { separator }
        }
    }

    private func rowText(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.leading)
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.textMuted)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.vertical, 8)
    }

    private func primaryButton(_ title: String, isEnabled: Bool = true, identifier: String,
                               action: @escaping () -> Void) -> some View {
        PrimaryButton(title: title, action: action)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.45)
            .accessibilityIdentifier(identifier)
    }

    private func secondaryButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// Shown when persistence is unavailable, so the calibration can't be saved.
struct CalibrationUnavailableView: View {
    @Environment(\.dismiss) private var dismiss

    private var palette: ColorPalette { ColorTokens.palette() }

    var body: some View {
        ZStack {
            AuraBackground(tab: .train)
            VStack(spacing: 16) {
                Text(CalibrationCopy.unavailable)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("calibrationUnavailable")
                Button(CalibrationCopy.close) { dismiss() }
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.tabActive)
                    .frame(minHeight: 48)
                    .accessibilityIdentifier("calibrationUnavailableCloseButton")
            }
            .padding(24)
        }
    }
}
