import SwiftUI

struct PostureHomeScreen: View {
    let state: PostureHomeState
    let send: (PostureHomeIntent) -> Void

    @Environment(\.motionPolicy) private var motionPolicy
    @State private var scrollOffset: CGFloat = 0
    @State private var titleFrame: CGRect = .zero

    private let palette = ColorTokens.palette()
    private let margin = Metrics.Spacing.screenMargin

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    tabRootHeader(compact: false)
                    if state.showsPersonaIntro {
                        PersonaIntroCard(
                            onDismiss: { send(.dismissPersonaIntro) },
                            onOpenSettings: { send(.openPersonaSettings) }
                        )
                        .padding(.top, 14)
                    }
                    liveCard.padding(.top, 14)
                    photoAssessmentSection.padding(.top, 18)
                    assessmentsSection.padding(.top, 18)
                    if let errorMessage = state.errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(palette.danger)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(palette.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, margin)
                .padding(.top, 4)
                .padding(.bottom, 20)
                .coordinateSpace(name: "posture.content")
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TabRootScrollOffsetPreferenceKey.self,
                            value: -proxy.frame(in: .named("posture.scroll")).minY
                        )
                    }
                }
            }
            .coordinateSpace(name: "posture.scroll")
            .scrollIndicators(.hidden)

            if isHeaderCollapsed {
                tabRootHeader(compact: true)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onPreferenceChange(TabRootScrollOffsetPreferenceKey.self) { scrollOffset = $0 }
        .onPreferenceChange(TabRootTitleFramePreferenceKey.self) { titleFrame = $0 }
        .animation(motionPolicy == .reduced ? nil : .easeInOut(duration: 0.18), value: isHeaderCollapsed)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { send(.appeared) }
        .environment(\.colorScheme, .dark)
    }

    private var isHeaderCollapsed: Bool {
        TabRootHeaderCollapse.shouldShowCompactBar(scrollOffset: scrollOffset, titleFrame: titleFrame)
    }

    @ViewBuilder
    private func tabRootHeader(compact: Bool) -> some View {
        let header = TabRootHeader(
            title: "Posture",
            height: 64,
            alignment: .top,
            compactBarAnchor: "posture.compactBar",
            leading: {
                Text("Posture")
                    .textStyle(.largeTitle)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 40, alignment: .center)
                    .designAnchor("posture.title")
                    .padding(.top, 20)
                    .tabRootTitleFrame(in: "posture.content")
            },
            largeTrailing: { EmptyView() },
            compactTrailing: { EmptyView() }
        )
        if compact { header.compactBar } else { header }
    }

    private var liveCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Live Posture Check")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .designAnchor("posture.liveTitle")

            Text("Stand in front of the camera and see your alignment measured as you move.")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineSpacing(2)
                .frame(maxWidth: 280, alignment: .leading)
                .frame(height: 61, alignment: .topLeading)
                .designAnchor("posture.liveDescription")

            Button { send(.startLiveCheck) } label: {
                HStack(spacing: 6) {
                    Image(material: "videocam")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Start Live Check")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundStyle(Color(hex: 0x2C3BB5))
                .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .designAnchor("posture.liveCTA")
            .padding(.top, 6)

            Text("Not recorded. Processed on this iPhone.")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .frame(maxWidth: .infinity, alignment: .center)
                .designAnchor("posture.livePrivacy")
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 234, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(GradientTokens.posture)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(.white.opacity(0.12))
                        .frame(width: 180, height: 180)
                        .offset(x: 50, y: -60)
                        .allowsHitTesting(false)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color(hex: 0x3C5ADC, alpha: 0.3), radius: 20, x: 0, y: 10)
        .designAnchor("posture.liveCard")
    }

    private var photoAssessmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
                Text("Photo Assessment")
                .font(.system(size: 21, weight: .black, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 24, alignment: .leading)
                .designAnchor("posture.photoAssessment")

            HStack(spacing: 10) {
                photoTile(
                    title: "Take Photo",
                    subtitle: "Front or side view",
                    icon: "photo_camera",
                    anchor: "posture.takePhoto"
                ) {
                    send(.takePhoto)
                }
                photoTile(
                    title: "Choose Photo",
                    subtitle: "From your library",
                    icon: "photo_library",
                    anchor: "posture.choosePhoto"
                ) {
                    send(.choosePhoto)
                }
            }
        }
    }

    private func photoTile(
        title: String,
        subtitle: String,
        icon: String,
        anchor: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(material: icon)
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(hex: 0x9FB0FF))
                Text(title)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .frame(height: 109, alignment: .topLeading)
            .background(palette.backgroundCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .designAnchor(anchor)
        }
        .buttonStyle(.plain)
    }

    private var assessmentsSection: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Assessments")
                    .font(.system(size: 20.5, weight: .black, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .designAnchor("posture.assessments")
                Spacer()
                Button("See all") { send(.openHistory) }
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.tabPostureActive)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("postureSeeAllButton")
            }
            .frame(height: 24)

            if state.assessments.isEmpty {
                EmptyStateTile(
                    title: "No assessments yet",
                    message: "Take or import a standing photo to start tracking geometric changes.",
                    icon: "figure.stand"
                )
            } else {
                ForEach(Array(state.assessments.prefix(3).enumerated()), id: \.element.id) { index, row in
                    let anchor: String? = switch index {
                    case 0: "posture.assessment.latest"
                    case 1: "posture.assessment.side"
                    case 2: "posture.assessment.baseline"
                    default: nil
                    }
                    assessmentRow(row, anchor: anchor)
                }
            }
        }
    }

    private func assessmentRow(_ row: PostureHomeAssessmentRow, anchor: String?) -> some View {
        Button { send(.openAssessment(row.id)) } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: 0x9FB0FF, alpha: 0.08))
                    StripedThumbnail()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .frame(width: 48, height: 60)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.dateLabel)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                    Text(row.viewLabel)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if row.isBaseline {
                    Text("Baseline")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(Color(hex: 0xC3CEFF))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color(hex: 0x9FB0FF, alpha: 0.16), in: Capsule())
                }
                Image(material: "chevron_right")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.textSubtle)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 80)
            .background(palette.backgroundCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .modifier(OptionalPostureAnchor(name: anchor))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                send(.setBaseline(id: row.id, isBaseline: !row.isBaseline))
            } label: {
                Label(row.isBaseline ? "Remove Baseline" : "Set as Baseline", systemImage: row.isBaseline ? "star.slash" : "star")
            }
            Button(role: .destructive) { send(.deleteAssessment(id: row.id)) } label: {
                Label("Delete Assessment", systemImage: "trash")
            }
        }
        .accessibilityIdentifier("postureAssessmentRow_\(row.id.uuidString)")
    }
}

private struct StripedThumbnail: View {
    var body: some View {
        Canvas { context, size in
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(path, with: .color(Color(hex: 0x9FB0FF, alpha: 0.18)), lineWidth: 6)
                x += 12
            }
        }
    }
}

private struct OptionalPostureAnchor: ViewModifier {
    let name: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let name { content.designAnchor(name) }
        else { content }
    }
}

struct PostureHistoryScreen: View {
    let state: PostureHomeState
    let send: (PostureHomeIntent) -> Void

    @Environment(\.dismiss) private var dismiss
    private let palette = ColorTokens.palette()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button(action: { dismiss() }) {
                    Label("Posture", systemImage: "chevron.left")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(palette.tabPostureActive)
                }
                .buttonStyle(.plain)
                .frame(height: 44, alignment: .leading)

                Text("Assessments")
                    .textStyle(.largeTitle)
                    .foregroundStyle(palette.textPrimary)

                if state.assessments.isEmpty {
                    EmptyStateTile(title: "No assessments saved", message: "Take or import a standing photo to begin.", icon: "figure.stand")
                } else {
                    ForEach(state.assessments) { row in
                        historyRow(row)
                    }
                }
            }
            .padding(.horizontal, Metrics.Spacing.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.colorScheme, .dark)
    }

    private func historyRow(_ row: PostureHomeAssessmentRow) -> some View {
        Button { send(.openAssessment(row.id)) } label: {
            HStack(spacing: 12) {
                StripedThumbnail()
                    .frame(width: 48, height: 60)
                    .background(Color(hex: 0x9FB0FF, alpha: 0.08), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.dateLabel).font(.system(size: 16, weight: .black, design: .rounded)).foregroundStyle(palette.textPrimary)
                    Text(row.viewLabel).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if row.isBaseline { Text("Baseline").font(.caption2.bold()).foregroundStyle(palette.tabPostureActive) }
                Image(systemName: "chevron.right").foregroundStyle(palette.textSubtle)
            }
            .padding(12)
            .background(palette.backgroundCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { send(.setBaseline(id: row.id, isBaseline: !row.isBaseline)) } label: {
                Label(row.isBaseline ? "Remove Baseline" : "Set as Baseline", systemImage: row.isBaseline ? "star.slash" : "star")
            }
            Button(role: .destructive) { send(.deleteAssessment(id: row.id)) } label: {
                Label("Delete Assessment", systemImage: "trash")
            }
        }
    }
}
