import SwiftUI

struct ExerciseDetailScreen: View {
    let state: ExerciseDetailState
    let send: (ExerciseDetailIntent) -> Void

    @Environment(\.exerciseCatalog) private var exerciseCatalog
    @Environment(\.preferences) private var preferences
    @Environment(\.motionPolicy) private var motionPolicy

    private var exercise: ExerciseDefinition? { exerciseCatalog.exercise(state.id) }

    var body: some View {
        ScrollView {
            if state.isAvailable, let exercise {
                content(exercise)
            } else {
                ContentUnavailableView("Exercise Unavailable", systemImage: "figure.strengthtraining.traditional")
                    .frame(maxWidth: .infinity, minHeight: 320)
            }
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .stickyCTA(bottomSpacing: Metrics.Spacing.medium + 3) {
            PrimaryButton(
                title: "Start Exercise",
                icon: "play.fill",
                variant: .gradient,
                size: .sticky
            ) {
                send(.startExercise)
            }
            .disabled(!state.isAvailable)
            .opacity(state.isAvailable ? 1 : 0.55)
            .designAnchor("cta.sticky")
        }
        .sheet(isPresented: guideBinding) {
            if let exercise {
                ExerciseGuideView(
                    exercise: exercise,
                    hasStarted: false,
                    isSpeaking: false,
                    onReadAloud: nil,
                    onStopReading: nil,
                    onShowVoiceCommands: nil,
                    onDone: { send(.startFromGuide) }
                )
                .presentationDetents([.large])
            }
        }
        .sheet(isPresented: targetEditorBinding) {
            if let exercise {
                ExerciseTargetEditor(exercise: exercise, preferences: preferences) {
                    send(.targetEditorDismissed)
                }
                .presentationDetents([.medium])
            }
        }
        .onAppear { send(.appeared) }
    }

    private func content(_ exercise: ExerciseDefinition) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            navigationHeader
            Color.clear.frame(height: 18)
            hero(exercise)
            Color.clear.frame(height: 16)
            titleBlock
            Color.clear.frame(height: 18)
            informationTiles
            Color.clear.frame(height: 18)
            targetCard
            Color.clear.frame(height: 18)
            watchesSection
            Color.clear.frame(height: 18)
            stepsSection
            Color.clear.frame(height: 20)
        }
        .padding(.horizontal, Metrics.Spacing.screenMargin)
        .padding(.top, 0)
        .padding(.bottom, 20)
    }

    private var navigationHeader: some View {
        HStack {
            Button { send(.back) } label: {
                HStack(spacing: 0) {
                    Image(material: "chevron_left")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Exercises")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(ColorTokens.palette().tabActive)
                .frame(height: 36)
                .contentShape(Rectangle())
                .designAnchor("exercise.back")
            }
            .buttonStyle(.plain)
            .padding(.leading, -6)
            Spacer(minLength: 0)
        }
        .frame(height: 44)
    }

    private func hero(_ exercise: ExerciseDefinition) -> some View {
        ZStack(alignment: .bottomLeading) {
            GradientTokens.linearGradient(from: state.gradient)
            ExerciseDemoStripes()
                .fill(.white.opacity(0.08))

            demonstration(exercise)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 42)
                .padding(.top, 4)

            Text("guide animation / demo figure")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.leading, 14)
                .padding(.bottom, 16)

            Button { send(.watchGuide) } label: {
                HStack(spacing: 6) {
                    Image(material: "play_circle")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Watch guide")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                }
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .frame(width: 143, height: 40)
                .background(Color(hex: 0x0E0B16, alpha: 0.62), in: Capsule())
                .contentShape(Capsule())
                .designAnchor("exercise.watchGuide")
            }
            .buttonStyle(.plain)
            .padding(.trailing, 14)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(height: 228)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.hero, style: .continuous))
        .designAnchor("exercise.guide")
    }

    @ViewBuilder
    private func demonstration(_ exercise: ExerciseDefinition) -> some View {
        if motionPolicy == .reduced {
            demoFigure(exercise, sample: exercise.guide.motion.sample(at: 0))
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { timeline in
                demoFigure(exercise, sample: exercise.guide.motion.sample(at: timeline.date.timeIntervalSinceReferenceDate))
            }
        }
    }

    private func demoFigure(_ exercise: ExerciseDefinition, sample: ArmMotionSample) -> some View {
        ExerciseDemoFigureView(
            angles: sample.angles,
            forearmPlane: exercise.guide.motion.forearmPlane,
            cameraView: exercise.cameraView,
            holdsDumbbells: exercise.guide.motion.holdsDumbbells,
            legs: sample.legs,
            torsoPitch: exercise.guide.motion.torsoPitch,
            tint: .white
        )
        .opacity(0.88)
        .accessibilityHidden(true)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(detailTitle)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .tracking(-0.5)
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 272, height: 67, alignment: .topLeading)
                .designAnchor("exercise.title")

            Text(state.muscles)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: 18, alignment: .leading)
                .designAnchor("exercise.subtitle")
        }
    }

    private var detailTitle: String {
        state.name == "Dumbbell Shoulder Press" ? "Dumbbell Shoulder\nPress" : state.name
    }

    private var informationTiles: some View {
        HStack(spacing: 10) {
            informationTile(
                title: "Equipment",
                value: state.equipmentText,
                icon: "fitness_center",
                anchor: "exercise.equipment"
            )
            informationTile(
                title: "Camera setup",
                value: state.cameraSetupText,
                icon: "photo_camera_front",
                anchor: "exercise.cameraSetup"
            )
        }
    }

    private func informationTile(title: String, value: String, icon: String, anchor: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(material: icon)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(ColorTokens.palette().tabActive)
                .frame(height: 26, alignment: .topLeading)
            Text(title)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textMuted)
                .frame(height: 15, alignment: .leading)
            Text(value)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 105)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .designAnchor(anchor)
    }

    private var targetCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("Sets")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(ColorTokens.palette().textPrimary)
                Spacer(minLength: 0)
                targetStepperButton(title: "Decrease sets", icon: "remove", intent: .decrementSets)
                Text("\(state.sets)")
                    .font(.system(size: 18, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(ColorTokens.palette().textPrimary)
                    .frame(minWidth: 16)
                    .contentTransition(.numericText())
                targetStepperButton(title: "Increase sets", icon: "add", intent: .incrementSets)
            }
            .frame(height: 53)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 1)
            }
            .designAnchor("exercise.sets")

            Button { send(.editReps) } label: {
                HStack {
                    Text("Reps per set")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().textPrimary)
                    Spacer()
                    Text(state.repsLabel)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(ColorTokens.palette().tabActive)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(height: 52)
            .accessibilityLabel("Reps per set, \(state.repsLabel). Tap to adjust target.")
            .designAnchor("exercise.reps")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func targetStepperButton(title: String, icon: String, intent: ExerciseDetailIntent) -> some View {
        Button { send(intent) } label: {
            Image(material: icon)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.1), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var watchesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The coach watches for")
                .font(.system(size: 19, weight: .black, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .frame(height: 22, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(state.watchesFor.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 10) {
                        Image(material: "visibility")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(ColorTokens.palette().success)
                            .frame(width: 26, height: 26)
                            .background(ColorTokens.palette().success.opacity(0.16), in: Circle())
                        Text(item)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: 0xE4DDF0))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(minHeight: 26, alignment: .leading)
                }
            }
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to do it")
                .font(.system(size: 19, weight: .black, design: .rounded))
                .foregroundStyle(ColorTokens.palette().textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 22, alignment: .leading)
                .designAnchor("exercise.coaching")

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(state.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(GradientTokens.linearGradient(from: state.gradient), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundStyle(ColorTokens.palette().textPrimary)
                            Text(step.detail)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(hex: 0xC4BBD6))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var guideBinding: Binding<Bool> {
        Binding(
            get: { state.isGuidePresented },
            set: { if !$0 { send(.dismissGuide) } }
        )
    }

    private var targetEditorBinding: Binding<Bool> {
        Binding(
            get: { state.isTargetEditorPresented },
            set: { if !$0 { send(.targetEditorDismissed) } }
        )
    }
}

private struct ExerciseDemoStripes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let span = rect.width + rect.height
        for offset in stride(from: -rect.height, through: rect.width, by: 16) {
            path.move(to: CGPoint(x: offset, y: 0))
            path.addLine(to: CGPoint(x: offset + rect.height, y: rect.height))
        }
        // Keep the path deterministic for the fixed design window.
        if span == 0 { path.addRect(.zero) }
        return path.strokedPath(StrokeStyle(lineWidth: 8))
    }
}
