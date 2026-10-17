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
    let session: WorkoutSession
    let presentation: WorkoutHUDPresentation
    let readings: [BodySide: ArmReading]
    /// The last rep's form values, shown with the measurements for tuning cue thresholds.
    let formReadings: [FormReading]
    let isPhoneTilted: Bool
    let micStatus: VoiceStatus
    let heardPhrase: String?
    @Binding var showMeasurements: Bool
    let onClose: () -> Void
    let onShowGuide: () -> Void
    let isCoachMuted: Bool
    let onMicrophoneTap: () -> Void
    let onToggleCoachVoice: () -> Void
    let onShowVoiceCommands: () -> Void
    let onCommand: (WorkoutCommand) -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var repSize: CGFloat = 64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmingEnd = false
    /// An exercise picked from the menu mid-set, waiting for confirmation that the set's reps can go.
    @State private var pendingExercise: ExerciseDefinition?
    @State private var repPulse = false

    var body: some View {
        VStack {
            VStack(spacing: 6) {
                topBar
                if isPhoneTilted {
                    Label("Phone tilted: stand it upright", systemImage: "iphone.gen3.radiowaves.left.and.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.6))
                        .clipShape(Capsule())
                        .accessibilityLabel("Phone tilted. Stand it upright for accurate counts.")
                }
                if let heardPhrase {
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
            .animation(.easeInOut(duration: 0.2), value: heardPhrase)
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
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
            }
            .accessibilityLabel("Close workout coach")
            .accessibilityIdentifier("closeWorkoutButton")

            Spacer(minLength: 8)

            // Tapping the title reopens the how-to guide.
            Button(action: onShowGuide) {
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text(session.exercise?.displayName ?? "Workout Coach")
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .multilineTextAlignment(.center)
                        if session.exercise != nil {
                            Image(systemName: "info.circle")
                                .font(.subheadline)
                        }
                    }
                    .foregroundStyle(.white)
                    Text(presentation.statusText)
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
            .disabled(session.exercise == nil)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Shows how to do this exercise")
            .accessibilityIdentifier("workoutGuideButton")

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                MicrophoneStatusView(status: micStatus, onTap: onMicrophoneTap, onShowCommands: onShowVoiceCommands)
                CoachVoiceButton(isMuted: isCoachMuted, action: onToggleCoachVoice)
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private var statusColor: Color {
        switch presentation.statusTone {
        case .endPosition: return WorkoutJointOverlayView.endPositionColor
        case .tracked: return WorkoutJointOverlayView.trackedColor
        case .attention: return .orange
        case .subdued: return .white.opacity(0.8)
        }
    }

    // MARK: - Bottom

    private var bottomPanel: some View {
        VStack(spacing: 8) {
            if presentation.showsRepProgress, let exercise = session.exercise {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(session.repCount)")
                        .font(.system(size: min(repSize, 96), weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .scaleEffect(repPulse ? 1.15 : 1, anchor: .bottomLeading)
                        .onChange(of: presentation.repEventCount) { old, new in
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
                        if let setLabel = presentation.setLabel {
                            Text(setLabel)
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        if let restLabel = presentation.restLabel {
                            Text(restLabel)
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(presentation.restTone == .waiting ? .yellow : WorkoutJointOverlayView.endPositionColor)
                        }
                        if let weight = session.currentWeights[exercise.id] {
                            Label(weight.label, systemImage: exercise.equipment == .band ? "lasso" : "scalemass")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.85))
                                .accessibilityLabel("Weight \(weight.spokenLabel)")
                        }
                        if let planProgressLabel = presentation.planProgressLabel {
                            Text(planProgressLabel)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                                .multilineTextAlignment(.trailing)
                        }
                        if exercise.countsArmsIndependently {
                            Text("L \(session.sideReps[.left] ?? 0) · R \(session.sideReps[.right] ?? 0)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilitySummary(exercise))
            }
            if showMeasurements {
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

            iconButton("arrow.counterclockwise", label: "Restart set", enabled: presentation.isSetInProgress) {
                onCommand(.restartSet)
            }
            iconButton("forward.end.fill", label: "Next set", enabled: presentation.canAdvanceSet) {
                onCommand(.nextSet)
            }
            Menu {
                if let plan = session.plan, session.isFollowingPlan {
                    // In a Saved Set, skip ahead in order, or leave it through the chooser, which explains.
                    Section(plan.name) {
                        Button { onCommand(.nextExercise) } label: {
                            Label("Skip to Next Exercise", systemImage: "forward.fill")
                        }
                        Button { onCommand(.changeExercise) } label: {
                            Label("Change Exercise\u{2026}", systemImage: "list.bullet")
                        }
                    }
                } else {
                    Section("Exercise") {
                        ForEach(session.exercises) { exercise in
                            Button { requestExercise(exercise) } label: {
                                if exercise.id == session.exerciseID {
                                    Label(exercise.displayName, systemImage: "checkmark")
                                } else {
                                    Text(exercise.displayName)
                                }
                            }
                        }
                    }
                }
                Button(action: onShowGuide) {
                    Label("How to Do It", systemImage: "questionmark.circle")
                }
                .disabled(session.exercise == nil)
                Button(action: onShowVoiceCommands) {
                    Label("Voice Commands", systemImage: "text.bubble")
                }
                Toggle(isOn: $showMeasurements) {
                    Label("Show Measurements", systemImage: "ruler")
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .frame(width: 40, height: 40)
            }
            .tint(.white)
            .accessibilityLabel("Exercise options")
            iconButton("stop.fill", label: "End workout", enabled: presentation.canEndWorkout) {
                confirmingEnd = true
            }
            .confirmationDialog("End this workout?", isPresented: $confirmingEnd, titleVisibility: .visible) {
                Button("End Workout", role: .destructive) { onCommand(.endWorkout) }
                Button("Keep Going", role: .cancel) {}
            }
        }
        .confirmationDialog(switchTitle, isPresented: Binding(get: { pendingExercise != nil },
                                                              set: { if !$0 { pendingExercise = nil } }),
                            titleVisibility: .visible) {
            if let exercise = pendingExercise {
                Button("Switch to \(exercise.displayName)", role: .destructive) { onCommand(.selectExercise(exercise.id)) }
            }
            Button("Keep Going", role: .cancel) {}
        }
    }

    /// Switching mid-set discards that set's reps, so confirm when there are any.
    private func requestExercise(_ exercise: ExerciseDefinition) {
        if exercise.id != session.exerciseID, presentation.isSetInProgress, session.sideReps.values.contains(where: { $0 > 0 }) {
            pendingExercise = exercise
        } else {
            onCommand(.selectExercise(exercise.id))
        }
    }

    private var switchTitle: String {
        let reps = max(session.sideReps[.left] ?? 0, session.sideReps[.right] ?? 0)
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
            if !formReadings.isEmpty {
                Text("Last rep: " + formReadings.map { "\($0.label) \($0.value)" }.joined(separator: " · "))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.white.opacity(0.85))
        .accessibilityElement(children: .combine)
    }

    private func measurement(for side: BodySide) -> Text {
        guard let reading = readings[side] else { return Text("\(side.shortLabel) –") }
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
            if let command = presentation.primaryButton.command { onCommand(command) }
        } label: {
            Label(presentation.primaryButton.label, systemImage: presentation.primaryButton.systemImageName)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
        .disabled(!presentation.primaryButton.isEnabled)
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

    private func accessibilitySummary(_ exercise: ExerciseDefinition) -> String {
        "\(session.repCount) reps of \(exercise.targetLabel). \(presentation.setLabel ?? "")."
    }
}
