import SwiftUI

/// HUD regions that floating content must avoid, in the workout overlay coordinate space.
struct WorkoutHUDRects: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

/// Compact top status and bottom rep counter with touch controls. The top stays small to leave
/// headroom for overhead movements.
struct WorkoutHUDView: View {
    let state: WorkoutHUDViewState
    let send: (WorkoutIntent) -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var repSize: CGFloat = 64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmingEnd = false
    /// An exercise picked from the menu mid-set, waiting for confirmation that the set's reps can go.
    @State private var pendingExercise: WorkoutHUDViewState.ExerciseOption?
    @State private var repPulse = false

    var body: some View {
        VStack {
            VStack(spacing: 6) {
                topBar
                if state.isPhoneTilted {
                    Label("Phone tilted: stand it upright", systemImage: "iphone.gen3.radiowaves.left.and.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.6))
                        .clipShape(Capsule())
                        .accessibilityLabel("Phone tilted. Stand it upright for accurate counts.")
                }
                if let heardPhrase = state.heardPhrase {
                    Label("Heard: \u{201C}\(heardPhrase)\u{201D}", systemImage: "waveform")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.6))
                        .clipShape(Capsule())
                        .transition(.opacity)
                        .accessibilityLabel("Heard \(heardPhrase)")
                }
            }
            .animation(.easeInOut(duration: 0.2), value: state.heardPhrase)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: WorkoutHUDRects.self, value: [proxy.frame(in: .named(WorkoutCoachView.coordinateSpace))])
            })
            Spacer()
            bottomPanel
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: WorkoutHUDRects.self, value: [proxy.frame(in: .named(WorkoutCoachView.coordinateSpace))])
                })
        }
    }

    // MARK: - Top

    private var topBar: some View {
        HStack(alignment: .center) {
            Button { send(.closeWorkout) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
            }
            .accessibilityLabel("Close workout coach")
            .accessibilityIdentifier("closeWorkoutButton")

            Spacer(minLength: 8)

            // Tapping the title reopens the how-to guide.
            Button { send(.showGuide) } label: {
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text(state.exercise?.displayName ?? "Workout Coach")
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .multilineTextAlignment(.center)
                        if state.exercise != nil {
                            Image(systemName: "info.circle")
                                .font(.subheadline)
                        }
                    }
                    .foregroundStyle(.white)
                    Text(state.presentation.statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(state.exercise == nil)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Shows how to do this exercise")
            .accessibilityIdentifier("workoutGuideButton")

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                MicrophoneStatusView(status: state.micStatus,
                                     onTap: { send(.microphoneTapped) },
                                     onShowCommands: { send(.showVoiceHelp) })
                CoachVoiceButton(isMuted: state.isCoachMuted) { send(.toggleCoachMute) }
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private var statusColor: Color {
        switch state.presentation.statusTone {
        case .endPosition: return WorkoutJointOverlayView.endPositionColor
        case .tracked: return WorkoutJointOverlayView.trackedColor
        case .attention: return .orange
        case .subdued: return .white.opacity(0.8)
        }
    }

    // MARK: - Bottom

    private var bottomPanel: some View {
        VStack(spacing: 8) {
            if state.presentation.showsRepProgress, let exercise = state.exercise {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(state.repCount)")
                        .font(.system(size: min(repSize, 96), weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .scaleEffect(repPulse ? 1.15 : 1, anchor: .bottomLeading)
                        .onChange(of: state.presentation.repEventCount) { old, new in
                            guard new > old, !reduceMotion else { return }
                            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { repPulse = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { repPulse = false }
                            }
                        }
                    Text("/ \(exercise.targetLabel)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let setLabel = state.presentation.setLabel {
                            Text(setLabel)
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        if let restLabel = state.presentation.restLabel {
                            Text(restLabel)
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(state.presentation.restTone == .waiting ? .yellow : WorkoutJointOverlayView.endPositionColor)
                        }
                        if let weight = state.currentWeights[exercise.id] {
                            Label(weight.label, systemImage: exercise.equipment == .band ? "lasso" : "scalemass")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.85))
                                .accessibilityLabel("Weight \(weight.spokenLabel)")
                        }
                        if let planProgressLabel = state.presentation.planProgressLabel {
                            Text(planProgressLabel)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                                .multilineTextAlignment(.trailing)
                        }
                        if exercise.countsArmsIndependently {
                            Text("L \(state.sideReps[.left] ?? 0) · R \(state.sideReps[.right] ?? 0)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilitySummary(exercise))
            }
            if state.showsMeasurements {
                measurementsRow
            }
            controls
        }
        .padding(10)
        .background(.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            primaryButton
                .frame(maxWidth: .infinity)

            iconButton("arrow.counterclockwise", label: "Restart set", enabled: state.presentation.isSetInProgress) {
                send(.restartSet)
            }
            iconButton("forward.end.fill", label: "Next set", enabled: state.presentation.canAdvanceSet) {
                send(.nextSet)
            }
            Menu {
                if let planName = state.planName, state.isFollowingPlan {
                    // In a Saved Set, skip ahead in order, or leave it through the chooser, which explains.
                    Section(planName) {
                        Button { send(.nextExercise) } label: {
                            Label("Skip to Next Exercise", systemImage: "forward.fill")
                        }
                        Button { send(.changeExercise) } label: {
                            Label("Change Exercise\u{2026}", systemImage: "list.bullet")
                        }
                    }
                } else {
                    Section("Exercise") {
                        ForEach(state.exerciseOptions) { exercise in
                            Button { requestExercise(exercise) } label: {
                                if exercise.id == state.exerciseID {
                                    Label(exercise.displayName, systemImage: "checkmark")
                                } else {
                                    Text(exercise.displayName)
                                }
                            }
                        }
                    }
                }
                Button { send(.showGuide) } label: {
                    Label("How to Do It", systemImage: "questionmark.circle")
                }
                .disabled(state.exercise == nil)
                Button { send(.showVoiceHelp) } label: {
                    Label("Voice Commands", systemImage: "text.bubble")
                }
                Toggle(isOn: Binding(get: { state.showsMeasurements }, set: { _ in send(.toggleMeasurements) })) {
                    Label("Show Measurements", systemImage: "ruler")
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .frame(width: 40, height: 40)
            }
            .tint(.white)
            .accessibilityLabel("Exercise options")
            iconButton("stop.fill", label: "End workout", enabled: state.presentation.canEndWorkout) {
                confirmingEnd = true
            }
            .confirmationDialog("End this workout?", isPresented: $confirmingEnd, titleVisibility: .visible) {
                Button("End Workout", role: .destructive) { send(.endWorkout) }
                Button("Keep Going", role: .cancel) {}
            }
        }
        .confirmationDialog(switchTitle, isPresented: Binding(get: { pendingExercise != nil },
                                                              set: { if !$0 { pendingExercise = nil } }),
                            titleVisibility: .visible) {
            if let exercise = pendingExercise {
                Button("Switch to \(exercise.displayName)", role: .destructive) { send(.chooseExercise(exercise.id)) }
            }
            Button("Keep Going", role: .cancel) {}
        }
    }

    /// Switching mid-set discards that set's reps, so confirm when there are any.
    private func requestExercise(_ exercise: WorkoutHUDViewState.ExerciseOption) {
        if exercise.id != state.exerciseID, state.presentation.isSetInProgress,
           state.sideReps.values.contains(where: { $0 > 0 }) {
            pendingExercise = exercise
        } else {
            send(.chooseExercise(exercise.id))
        }
    }

    private var switchTitle: String {
        let reps = max(state.sideReps[.left] ?? 0, state.sideReps[.right] ?? 0)
        return "Discard this set's \(reps == 1 ? "1 rep" : "\(reps) reps")?"
    }

    /// Live signals per arm, for checking the counting thresholds on device, and the last rep's form
    /// values for checking the coaching thresholds.
    private var measurementsRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 14) {
                ForEach(BodySide.allCases, id: \.self) { side in
                    measurement(for: side)
                }
                Spacer(minLength: 0)
            }
            if !state.formReadings.isEmpty {
                Text("Last rep: " + state.formReadings.map { "\($0.label) \($0.value)" }.joined(separator: " · "))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.white.opacity(0.85))
        .accessibilityElement(children: .combine)
    }

    private func measurement(for side: BodySide) -> Text {
        guard let reading = state.readings[side] else { return Text("\(side.shortLabel) –") }
        let symbol: String
        switch reading.zone {
        case .top: symbol = "arrow.up.circle.fill"
        case .bottom: symbol = "arrow.down.circle.fill"
        case .middle: symbol = "circle.dotted"
        }
        return Text("\(side.shortLabel) \(String(format: "%.2f", reading.signal)) · \(Int(reading.elbowAngle.rounded()))° ")
            + Text(Image(systemName: symbol))
    }

    private var primaryButton: some View {
        Button {
            switch state.presentation.primaryButton.kind {
            case .start, .startSet: send(.start)
            case .pause: send(.pause)
            case .resume: send(.resume)
            case .disabled: break
            }
        } label: {
            Label(state.presentation.primaryButton.label, systemImage: state.presentation.primaryButton.systemImageName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
        .disabled(!state.presentation.primaryButton.isEnabled)
    }

    private func iconButton(_ systemImage: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 40, height: 40)
        }
        .tint(.white)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func accessibilitySummary(_ exercise: WorkoutHUDExercise) -> String {
        "\(state.repCount) reps of \(exercise.targetLabel). \(state.presentation.setLabel ?? "")."
    }
}
