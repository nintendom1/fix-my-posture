import SwiftUI

struct ProgressScreen: View {
    let viewModel: ProgressViewModel

    @Environment(\.motionPolicy) private var motionPolicy
    @State private var scrollOffset: CGFloat = 0
    @State private var titleFrame: CGRect = .zero

    private let palette = ColorTokens.palette()

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 0) {
                    tabRootHeader(compact: false)
                    VStack(spacing: 18) {
                        weekCard
                        workoutsChartCard
                        weightChartCard
                        recentSection
                        postureCard
                    }
                    .padding(.top, 14)
                }
                .padding(.horizontal, Metrics.Spacing.screenMargin)
                .padding(.top, 4)
                .padding(.bottom, 20)
                .coordinateSpace(name: "progress.content")
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TabRootScrollOffsetPreferenceKey.self,
                            value: -proxy.frame(in: .named("progress.scroll")).minY
                        )
                    }
                }
            }
            .coordinateSpace(name: "progress.scroll")
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
        .onAppear { viewModel.send(.appeared) }
        .environment(\.colorScheme, .dark)
    }

    private var isHeaderCollapsed: Bool {
        TabRootHeaderCollapse.shouldShowCompactBar(scrollOffset: scrollOffset, titleFrame: titleFrame)
    }

    @ViewBuilder
    private func tabRootHeader(compact: Bool) -> some View {
        let header = TabRootHeader(
            title: "Progress",
            height: 64,
            alignment: .top,
            compactBarAnchor: "progress.compactBar",
            leading: {
                Text("Progress")
                    .textStyle(.largeTitle)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 40, alignment: .center)
                    .designAnchor("progress.title")
                    .padding(.top, 20)
                    .tabRootTitleFrame(in: "progress.content")
            },
            largeTrailing: { EmptyView() },
            compactTrailing: { EmptyView() }
        )
        if compact { header.compactBar } else { header }
    }

    private var weekCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(palette.textPrimary.opacity(0.92))
                Spacer()
                Text(viewModel.state.weeklyStats.weekRangeLabel)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary.opacity(0.85))
            }

            HStack(spacing: 6) {
                metric(value: String(viewModel.state.weeklyStats.workoutCount), title: "Workouts", anchor: "progress.stats.workouts", anchorWidth: 16.5)
                metric(value: String(viewModel.state.weeklyStats.setCount), title: "Sets", anchor: "progress.stats.sets", anchorWidth: 31.5)
                metric(value: String(viewModel.state.weeklyStats.repCount), title: "Reps", anchor: "progress.stats.reps", anchorWidth: 47.5)
                metric(value: viewModel.state.weeklyStats.durationLabel, title: "Time", anchor: nil, anchorWidth: nil)
            }

            HStack(spacing: 6) {
                let labels = ["M", "T", "W", "T", "F", "S", "S"]
                ForEach(labels.indices, id: \.self) { index in
                    VStack(spacing: 4) {
                        ZStack {
                            let isActive = viewModel.state.weeklyStats.activeDays[index]
                            let isToday = index == viewModel.state.weeklyStats.todayIndex
                            Circle()
                                .fill(isActive ? .white : Color.white.opacity(isToday ? 0.35 : 0.14))
                            if isActive {
                                Image(material: "check")
                                    .font(.system(size: 17, weight: .black, design: .rounded))
                                    .foregroundStyle(Color(hex: 0x3A1FA0))
                            }
                        }
                        .frame(width: 32, height: 32)
                        Text(labels[index])
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(palette.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 174)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(GradientTokens.progress)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
        .shadow(color: Color(hex: 0x503CDC, alpha: 0.3), radius: 20, x: 0, y: 10)
        .designAnchor("progress.week")
    }

    private func metric(value: String, title: String, anchor: String?, anchorWidth: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let anchorWidth {
                Text(value)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(width: anchorWidth, height: 31, alignment: .leading)
                    .modifier(OptionalDesignAnchor(name: anchor))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(value)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(height: 31, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(title)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var workoutsChartCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Workouts per week")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("last 6 weeks")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.textMuted)
            }
            Color.clear
                .frame(height: 110)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: 176)
        .background(cardBackground(cornerRadius: 24))
        .designAnchor("progress.activity")
    }

    private var weightChartCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Shoulder Press weight")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                Text("15 → 20 lb")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.success)
                    .lineLimit(1)
            }
            Color.clear
                .frame(height: 70)
                .accessibilityHidden(true)
            Text("Heaviest weight per session · last 6 sessions")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(palette.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: 164)
        .background(cardBackground(cornerRadius: 24))
        .designAnchor("progress.weight")
    }

    private var recentSection: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center) {
                Text("Recent workouts")
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 175.5, height: 24, alignment: .leading)
                    .designAnchor("progress.recent")
                Spacer()
                Button("See all") { viewModel.send(.openHistory) }
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.tabActive)
                    .buttonStyle(.plain)
            }
            ForEach(Array(viewModel.state.recentWorkouts.enumerated()), id: \.element.id) { index, workout in
                Button { viewModel.send(.openHistory) } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(recentGradient(for: workout, index: index))
                            .frame(width: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workout.name)
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(1)
                            Text(workout.meta)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(workout.day)
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(palette.textMuted)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .designAnchor(index == 0 ? "progress.workout.upperBody" : index == 1 ? "progress.workout.quickStrength" : "progress.workout.recent\(index)")
            }
        }
    }

    private func recentGradient(for workout: WeeklyStats.RecentWorkout, index: Int) -> LinearGradient {
        switch workout.name {
        case "Upper Body":
            return GradientTokens.trainHero
        case "Quick Strength":
            return GradientTokens.linearGradient(from: AirSquatExercise.definition().presentation.gradient)
        default:
            return index.isMultiple(of: 2) ? GradientTokens.progress : GradientTokens.posture
        }
    }

    private var postureCard: some View {
        Button { viewModel.send(.openPosture) } label: {
            HStack(spacing: 12) {
                Image(material: "accessibility_new")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(LinearGradient(
                        colors: [Color(hex: 0x4B6CF7), Color(hex: 0x8A7DFF)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Posture")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                    Text(viewModel.state.postureSummary)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(material: "chevron_right")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.textSubtle)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Color(hex: 0x5078FF, alpha: 0.10), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color(hex: 0x7896FF, alpha: 0.20), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func cardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(palette.backgroundCard)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(palette.borderCard, lineWidth: 1)
            }
    }
}

private struct OptionalDesignAnchor: ViewModifier {
    let name: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let name { content.designAnchor(name) }
        else { content }
    }
}
