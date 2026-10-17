import SwiftUI

struct AssessmentScreen: View {
    let viewModel: AssessmentViewModel
    var showsToolbarMenu = true

    @Environment(\.dismiss) private var dismiss
    @State private var showLandmarkEditor = false
    @State private var showDeveloperDiagnostics = false

    private let palette = ColorTokens.palette()

    init(viewModel: AssessmentViewModel, showsToolbarMenu: Bool = true) {
        self.viewModel = viewModel
        self.showsToolbarMenu = showsToolbarMenu
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                titleBlock
                reportPhoto
                measurements
                Text(viewModel.state.notice)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.textSubtle)
                    .lineSpacing(2)
                if let message = viewModel.state.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(palette.danger)
                }
            }
            .padding(.horizontal, Metrics.Spacing.screenMargin)
            .padding(.top, 0)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showLandmarkEditor) {
            if let image = viewModel.image {
                LandmarkEditingView(
                    pose: Binding(
                        get: { viewModel.assessment.pose },
                        set: { viewModel.saveEditedPose($0) }
                    ),
                    image: image,
                    onSave: { pose in
                        viewModel.saveEditedPose(pose)
                        showLandmarkEditor = false
                    },
                    onCancel: { showLandmarkEditor = false }
                )
            } else {
                ContentUnavailableView("Photo Unavailable", systemImage: "photo")
            }
        }
        .sheet(isPresented: $showDeveloperDiagnostics) {
            DeveloperDebugView(assessment: viewModel.assessment, processingDuration: 0)
        }
    }

    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 30, weight: .medium, design: .rounded))
                    Text("Posture")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                }
                    .foregroundStyle(palette.tabPostureActive)
                    .frame(width: 92, height: 36, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .alignmentGuide(.leading) { $0[.leading] + 6 }
            .designAnchor("assessment.back")
            .frame(height: 44, alignment: .leading)

            Spacer()
            if showsToolbarMenu {
                Menu {
                    Button { showLandmarkEditor = true } label: {
                        Label("Edit Points", systemImage: "pencil")
                    }
                    Button { showDeveloperDiagnostics = true } label: {
                        Label("Developer Diagnostics", systemImage: "ladybug")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.tabPostureActive)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Assessment options")
            }
        }
        .frame(height: 44)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(viewModel.state.dateText)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .tracking(-0.5)
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .designAnchor("assessment.date")
            Text(viewModel.state.viewComparisonText)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .designAnchor("assessment.view")
        }
    }

    private var reportPhoto: some View {
        PostureReportView(
            image: viewModel.image,
            pose: displayPose,
            view: viewModel.assessment.view,
            measurements: viewModel.assessment.measurements,
            sourcePose: viewModel.assessment.pose,
            horizonContext: viewModel.assessment.horizonContext,
            referenceProvider: viewModel.referenceProvider,
            imageHeight: 330,
            imageCornerRadius: 28,
            showsReportControls: false
        )
        .overlay(alignment: .bottomTrailing) {
            Button { showLandmarkEditor = true } label: {
                Label("Adjust points", systemImage: "pencil")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12.5)
                    .frame(height: 38)
                    .background(Color(hex: 0x0E0B16, alpha: 0.72), in: Capsule())
                    .designAnchor("assessment.adjustPoints")
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
            .padding(.bottom, 12)
        }
        .designAnchor("assessment.photo")
    }

    private var displayPose: BodyPose {
        guard let image = viewModel.image else { return viewModel.assessment.pose }
        return ImageNormalizer.mapPoseToOrientation(viewModel.assessment.pose, orientation: image.imageOrientation)
    }

    private var measurements: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Measurements")
                .font(.system(size: 19, weight: .black, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 22, alignment: .leading)
                .designAnchor("assessment.measurements")
                .padding(.bottom, 3)

            ForEach(Array(viewModel.state.measurements.enumerated()), id: \.element.id) { index, row in
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(palette.textPrimary)
                        if let baselineText = row.baselineText {
                            Text(baselineText)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(palette.textSubtle)
                                .modifier(AssessmentRowAnchor(name: baselineAnchor(for: row.id)))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(row.valueText)
                            .font(.system(size: 15.5, weight: .black, design: .rounded))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .modifier(AssessmentRowAnchor(name: valueAnchor(for: row.id)))
                        if let deltaText = row.deltaText {
                            Text(deltaText)
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(palette.tabPostureActive)
                                .lineLimit(1)
                                .modifier(AssessmentRowAnchor(name: deltaAnchor(for: row.id)))
                        }
                    }
                }
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .overlay(alignment: .bottom) {
                    if index < viewModel.state.measurements.count - 1 {
                        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                    }
                }
                .modifier(AssessmentRowAnchor(name: row.id == .headTiltAngle ? "assessment.headTilt" : row.id == .shoulderLineAngle ? "assessment.shoulderLine" : row.id == .torsoLateralDeviation ? "assessment.torsoDeviation" : row.id == .hipLineAngle ? "assessment.hipLine" : nil))
            }
        }
    }

    private func valueAnchor(for id: MeasurementID) -> String? {
        switch id {
        case .headTiltAngle: return "assessment.headTilt.value"
        case .shoulderLineAngle: return "assessment.shoulderLine.value"
        case .torsoLateralDeviation: return "assessment.torsoDeviation.value"
        case .hipLineAngle: return "assessment.hipLine.value"
        default: return nil
        }
    }

    private func deltaAnchor(for id: MeasurementID) -> String? {
        switch id {
        case .headTiltAngle: return "assessment.headTilt.delta"
        case .shoulderLineAngle: return "assessment.shoulderLine.delta"
        case .torsoLateralDeviation: return "assessment.torsoDeviation.delta"
        case .hipLineAngle: return "assessment.hipLine.delta"
        default: return nil
        }
    }

    private func baselineAnchor(for id: MeasurementID) -> String? {
        switch id {
        case .headTiltAngle: return "assessment.headTilt.baseline"
        case .shoulderLineAngle: return "assessment.shoulderLine.baseline"
        case .torsoLateralDeviation: return "assessment.torsoDeviation.baseline"
        case .hipLineAngle: return "assessment.hipLine.baseline"
        default: return nil
        }
    }
}

private struct AssessmentRowAnchor: ViewModifier {
    let name: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let name { content.designAnchor(name) }
        else { content }
    }
}
