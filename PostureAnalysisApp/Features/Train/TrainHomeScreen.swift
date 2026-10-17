import SwiftUI

struct TrainHomeScreen: View {
    let state: TrainHomeState
    let send: (TrainHomeIntent) -> Void
    var initialScrollOffset: CGFloat? = nil

    @Environment(\.motionPolicy) private var motionPolicy
    @State private var tabRootScrollOffset: CGFloat = 0
    @State private var tabRootTitleFrame: CGRect = .zero

    private let horizontalMargin: CGFloat = 20
    private let heroHeight: CGFloat = 303.5
    private let tileHeight: CGFloat = 158.5

    private let tileColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                        tabRootHeader(compact: false)
                        hero
                        quickStart
                        if let lastWorkout = state.lastWorkout {
                            lastWorkoutCard(lastWorkout)
                        }
                }
                .padding(.horizontal, horizontalMargin)
                .padding(.top, 4)
                .padding(.bottom, 20)
                .offset(y: -(initialScrollOffset ?? 0))
                .coordinateSpace(name: "train.content")
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TabRootScrollOffsetPreferenceKey.self,
                            value: -proxy.frame(in: .named("train.scroll")).minY
                        )
                    }
                }
            }
            .coordinateSpace(name: "train.scroll")
            .scrollIndicators(.hidden)

            if isTabRootHeaderCollapsed {
                tabRootHeader(compact: true)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onPreferenceChange(TabRootScrollOffsetPreferenceKey.self) { tabRootScrollOffset = $0 }
        .onPreferenceChange(TabRootTitleFramePreferenceKey.self) { tabRootTitleFrame = $0 }
        .animation(motionPolicy == .reduced ? nil : .easeInOut(duration: 0.18), value: isTabRootHeaderCollapsed)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: routinePickerBinding) {
            routinePickerSheet
        }
        .onAppear { send(.appeared) }
    }

    private var isTabRootHeaderCollapsed: Bool {
        TabRootHeaderCollapse.shouldShowCompactBar(
            scrollOffset: tabRootScrollOffset,
            titleFrame: tabRootTitleFrame
        )
    }

    @ViewBuilder
    private func tabRootHeader(compact: Bool) -> some View {
        let header = TabRootHeader(
            title: "Train",
            height: 64,
            alignment: .top,
            compactBarAnchor: "train.compactBar",
            leading: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(state.dateLabel)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textSecondary)
                    Text("Train")
                        .textStyle(.largeTitle)
                        .foregroundStyle(ColorTokens.palette().textPrimary)
                        .scaleEffect(x: 1.16, y: 1, anchor: .leading)
                        .frame(width: 98.5, height: 40, alignment: .leading)
                        .designAnchor("train.title")
                        .tabRootTitleFrame(in: "train.content")
                }
            },
            largeTrailing: { settingsButton(anchor: "train.settings").padding(.top, 20) },
            compactTrailing: { settingsButton(anchor: "train.compactBar.settings") }
        )
        if compact { header.compactBar } else { header }
    }

    private func settingsButton(anchor: String) -> some View {
        Button { send(.openSettings) } label: {
            Image(material: "settings")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.08), in: Circle())
                .contentShape(Circle())
                .designAnchor(anchor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }

    private var hero: some View {
        Group {
            if let routine = state.heroRoutine {
                routineHero(routine)
            } else {
                EmptyStateTile(
                    title: "Create a routine",
                    message: "Save a few exercises together and start them here.",
                    icon: "list.number",
                    actionTitle: "Create Routine",
                    action: { send(.createRoutine) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: heroHeight)
        .background {
            if state.heroRoutine != nil {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(GradientTokens.trainHero)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color(hex: 0x7C4DFF, alpha: 0.32), radius: 20, x: 0, y: 10)
        .designAnchor("train.hero")
    }

    private func routineHero(_ routine: TrainHomeRoutinePresentation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("READY TO TRAIN?")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.9))
                .frame(height: 16, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(routine.name)
                    .font(Typography.title)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 31.5, alignment: .leading)
                    .designAnchor("train.hero.title")

                Text(routine.summaryWithEstimate)
                    .font(Typography.body)
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 18, alignment: .leading)
                    .designAnchor("train.hero.subtitle")
            }

            ChipFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(Array(routine.chips.enumerated()), id: \.offset) { _, chip in
                    Text(chip)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.2), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56, alignment: .topLeading)

            PrimaryButton(
                title: "Start Routine",
                icon: "play.fill",
                iconFontSize: 22,
                contentSpacing: 6,
                variant: .white
            ) {
                send(.startRoutine)
            }
            .frame(maxWidth: .infinity)
            .designAnchor("train.hero.cta")
            .padding(.top, 4)
            .disabled(!routine.canStart)
            .opacity(routine.canStart ? 1 : 0.55)

            HStack(spacing: 0) {
                if let lastDoneLabel = routine.lastDoneLabel {
                    Text("Last done \(lastDoneLabel) · ")
                        .foregroundStyle(.white.opacity(0.86))
                }
                Button("Pick another") { send(.pickAnother) }
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
            }
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 16)
            .designAnchor("train.hero.lastDone")
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(alignment: .topTrailing) {
            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: 200, height: 200)
                .offset(x: 60, y: -70)
                .allowsHitTesting(false)
        }
    }

    private var routinePickerSheet: some View {
        NavigationStack {
            List {
                ForEach(state.routineChoices, id: \.id) { routine in
                    Button { send(.selectRoutine(routine.id)) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(routine.name)
                                .font(.headline)
                                .foregroundStyle(ColorTokens.palette().textPrimary)
                            Text(routine.summaryWithEstimate)
                                .font(.subheadline)
                                .foregroundStyle(ColorTokens.palette().textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(hex: 0x1A1526))
            .navigationTitle("Pick another routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { send(.dismissRoutinePicker) }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(28)
        .presentationBackground(Color(hex: 0x1A1526))
    }

    private var routinePickerBinding: Binding<Bool> {
        Binding(
            get: { state.isRoutinePickerPresented },
            set: { if !$0 { send(.dismissRoutinePicker) } }
        )
    }

    private var quickStart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("Quick Start")
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .frame(width: 117, height: 24, alignment: .leading)
                    .designAnchor("train.quickStart.title")

                Spacer(minLength: 8)

                Button { send(.openLibrary) } label: {
                    Text("All Exercises")
                        .font(Font.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().tabActive)
                        .frame(height: 18, alignment: .center)
                        .contentShape(Rectangle())
                        .designAnchor("train.quickStart.all")
                        .padding(.top, 5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("All Exercises")
            }
            .frame(height: 24)

            LazyVGrid(columns: tileColumns, alignment: .center, spacing: 10) {
                ForEach(Array(state.exercises.enumerated()), id: \.element.id) { index, exercise in
                    Button { send(.startExercise(exercise.id)) } label: {
                        ExerciseTileView(
                            exercise: exercise,
                            thumbAnchor: "train.quickStart.tile\(index).thumb"
                        )
                            .frame(height: tileHeight)
                            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(exercise.name), \(exercise.target)")
                    .designAnchor("train.quickStart.tile\(index)")
                }
            }
        }
    }

    private func lastWorkoutCard(_ workout: TrainLastWorkoutPresentation) -> some View {
        Button { send(.openHistory) } label: {
            HStack(spacing: 14) {
                Image(material: "check")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x06321F))
                    .frame(width: 44, height: 44)
                    .background(GradientTokens.success, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.dateLabel)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textMuted)
                    Text(workout.summary)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(material: "chevron_right")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().textSubtle)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .frame(height: 86)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .designAnchor("train.lastWorkout")
    }
}

private struct ExerciseTileView: View {
    let exercise: TrainExerciseTile
    let thumbAnchor: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(GradientTokens.linearGradient(from: exercise.gradient))
                Image(systemName: exercise.symbolName)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .accessibilityHidden(true)
                    .padding(8)
            }
            .frame(height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .designAnchor(thumbAnchor)

            Text(exercise.name)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 17.25, maxHeight: 17.25, alignment: .leading)

            Text(exercise.target)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textMuted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                }
        }
    }
}

private struct ChipFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
