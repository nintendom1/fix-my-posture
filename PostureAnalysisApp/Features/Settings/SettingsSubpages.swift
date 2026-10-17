import SwiftUI

struct SettingsRestPolicyPage: View {
    @Bindable var viewModel: SettingsViewModel

    private let choices: [(String, String, RestPolicy)] = [
        ("Exercise default", "Use the rest duration set by each exercise.", .exerciseDefault),
        ("30 seconds", "", .fixed(seconds: 30)),
        ("60 seconds", "", .fixed(seconds: 60)),
        ("90 seconds", "", .fixed(seconds: 90)),
        ("120 seconds", "", .fixed(seconds: 120))
    ]

    var body: some View {
        SettingsSubpage(title: "Rest between sets") {
            SettingsChoiceCard {
                ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                    SettingsChoiceRow(
                        title: choice.0,
                        detail: choice.1,
                        isSelected: viewModel.restPolicy == choice.2,
                        showsSeparator: index > 0
                    ) {
                        viewModel.restPolicy = choice.2
                    }
                }
            }
        }
    }
}

struct SettingsWeightUnitPage: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        SettingsSubpage(title: "Weight units") {
            SettingsChoiceCard {
                SettingsChoiceRow(title: "Pounds (lb)", isSelected: viewModel.weightUnit == .lb) {
                    viewModel.weightUnit = .lb
                }
                SettingsChoiceRow(title: "Kilograms (kg)", isSelected: viewModel.weightUnit == .kg, showsSeparator: true) {
                    viewModel.weightUnit = .kg
                }
            }
        }
    }
}

struct SettingsCameraFramingPage: View {
    @Bindable var viewModel: SettingsViewModel

    private let cameraBlue = Color(hex: 0x5078FF, alpha: 0.9)

    var body: some View {
        SettingsSubpage(title: "Camera & framing") {
            SettingsChoiceCard {
                SettingsRow(
                    icon: "straighten",
                    title: "Camera tilt compensation",
                    iconColor: cameraBlue,
                    toggle: binding(\.cameraTiltCompensationEnabled)
                )
                SettingsRow(
                    icon: "photo_camera",
                    title: "Horizon line",
                    iconColor: cameraBlue,
                    toggle: binding(\.showHorizonLine),
                    showsSeparator: true
                )
                SettingsRow(
                    icon: "visibility",
                    title: "Alignment targets",
                    iconColor: cameraBlue,
                    toggle: binding(\.showAlignmentTargets),
                    showsSeparator: true
                )
                HStack(spacing: 12) {
                    SettingsIconTile(icon: "graphic_eq", color: cameraBlue)
                    Text("Feedback refresh rate")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Picker("Feedback refresh rate", selection: binding(\.feedbackRefreshRate)) {
                        Text("2 / sec").tag(2)
                        Text("5 / sec").tag(5)
                        Text("10 / sec").tag(10)
                    }
                    .pickerStyle(.menu)
                    .tint(ColorTokens.palette().textMuted)
                }
                .frame(minHeight: 53)
                .padding(.horizontal, 14)
                .padding(.top, 1)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                }
            }
            Text("These controls apply to live camera feedback and saved photo reports.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textSubtle)
                .padding(.horizontal, 4)
        }
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<SettingsViewModel, Value>) -> Binding<Value> {
        Binding(get: { viewModel[keyPath: keyPath] }, set: { viewModel[keyPath: keyPath] = $0 })
    }
}

struct SettingsPostureDisplayPage: View {
    @Bindable var viewModel: SettingsViewModel

    private let cameraBlue = Color(hex: 0x5078FF, alpha: 0.9)

    var body: some View {
        SettingsSubpage(title: "Posture display") {
            SettingsChoiceCard {
                SettingsRow(
                    icon: "straighten",
                    title: "Horizon line",
                    iconColor: cameraBlue,
                    toggle: Binding(get: { viewModel.showHorizonLine }, set: { viewModel.showHorizonLine = $0 })
                )
            }
            Text("Report overlays")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textMuted)
                .textCase(.uppercase)
                .tracking(1)
                .padding(.horizontal, 4)
                .padding(.top, 8)
            SettingsChoiceCard {
                SettingsInfoRow(title: "Alignment targets", detail: "Available in each report; not saved.")
                SettingsInfoRow(title: "Measured landmarks", detail: "Available in each report; not saved.", showsSeparator: true)
                SettingsInfoRow(title: "Alignment reference", detail: "Available in each report; not saved.", showsSeparator: true)
                SettingsInfoRow(title: "Measurement callouts", detail: "Available in each report; not saved.", showsSeparator: true)
            }
        }
    }
}

struct SettingsPrivacyPage: View {
    var body: some View {
        SettingsTextPage(
            title: "Privacy",
            paragraphs: [
                "Posture photos and live camera frames are analyzed on this iPhone. Live camera frames are never recorded.",
                "A photo assessment is saved on this device only when you choose to save it. The app has no network or cloud processing."
            ]
        )
    }
}

struct SettingsAboutPage: View {
    var body: some View {
        SettingsTextPage(
            title: "About & medical notice",
            paragraphs: [
                "Fix My Posture measures body landmarks and angles from an image.",
                "Measurements are geometric observations relative to your own baseline. They are not medical advice or a diagnosis, and the app is not a medical device."
            ]
        )
    }
}

struct SettingsDeveloperDiagnosticsPage: View {
    let viewModel: SettingsViewModel

    var body: some View {
        SettingsSubpage(title: "Developer diagnostics") {
            Text("Diagnostics are available from an assessment report. Open a saved report and tap Developer Diagnostics.")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(ColorTokens.palette().backgroundCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            if viewModel.latestAssessmentID != nil {
                Button("Open latest assessment", action: viewModel.openLatestAssessment)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().tabActive)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(ColorTokens.palette().backgroundCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}

struct SettingsTextPage: View {
    let title: String
    let paragraphs: [String]

    var body: some View {
        SettingsSubpage(title: title) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .background(ColorTokens.palette().backgroundCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

private struct SettingsSubpage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            AuraBackground(tab: .train)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Color(hex: 0x0E0B16), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct SettingsChoiceCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(ColorTokens.palette().backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct SettingsChoiceRow: View {
    let title: String
    var detail = ""
    let isSelected: Bool
    var showsSeparator = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textPrimary)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(ColorTokens.palette().textMuted)
                    }
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(material: "check")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().tabActive)
                }
            }
            .frame(minHeight: detail.isEmpty ? 52 : 64)
            .padding(.horizontal, 16)
            .padding(.top, showsSeparator ? 1 : 0)
            .overlay(alignment: .top) {
                if showsSeparator { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsInfoRow: View {
    let title: String
    let detail: String
    var showsSeparator = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
            Text(detail)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, showsSeparator ? 1 : 0)
        .overlay(alignment: .top) {
            if showsSeparator { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
        }
    }
}

struct SettingsIconTile: View {
    let icon: String
    let color: Color

    var body: some View {
        Image(material: icon)
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
