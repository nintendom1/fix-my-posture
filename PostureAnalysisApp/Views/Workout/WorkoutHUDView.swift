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
    let now: TimeInterval
    let onClose: () -> Void
    let onCommand: (WorkoutCommand) -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var repSize: CGFloat = 64
    @State private var confirmingEnd = false

    var body: some View {
        VStack {
            topBar
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

            VStack(spacing: 2) {
                Text(session.exercise?.displayName ?? "Workout Coach")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            // Balances the close button so the title stays centered.
            Color.clear
                .frame(width: 32, height: 32)
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private var statusText: String {
        switch session.phase {
        case .choosingExercise, .changingExercise: return "Choose an exercise"
        case .framing: return session.framing.guidance?.shortText ?? "Hold still"
        case .ready: return "Ready"
        case .exercising:
            return session.isCounting ? "Counting" : (session.framing.guidance?.shortText ?? FramingGuidance.stepIntoView.shortText)
        case .paused: return "Paused"
        case .resting: return "Resting"
        case .exerciseComplete: return "Exercise complete"
        case .ended: return "Workout ended"
        }
    }

    private var statusColor: Color {
        switch session.phase {
        case .ready: return WorkoutJointOverlayView.endPositionColor
        case .exercising: return session.isCounting ? WorkoutJointOverlayView.trackedColor : .orange
        case .framing: return .orange
        default: return .white.opacity(0.8)
        }
    }

    // MARK: - Bottom

    private var bottomPanel: some View {
        VStack(spacing: 8) {
            if let exercise = session.exercise {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(session.repCount)")
                        .font(.system(size: min(repSize, 96), weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("/ \(exercise.targetLabel)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(setLabel(exercise))
                            .font(.headline)
                            .foregroundStyle(.white)
                        if let rest = session.restRemaining(at: now) {
                            Text("Rest \(Self.format(rest))")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(rest > 0 ? .yellow : WorkoutJointOverlayView.endPositionColor)
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

            iconButton("arrow.counterclockwise", label: "Restart set", enabled: isSetInProgress) {
                onCommand(.restartSet)
            }
            iconButton("forward.end.fill", label: "Next set", enabled: isSetInProgress || session.phase == .resting) {
                onCommand(.nextSet)
            }
            Menu {
                ForEach(session.exercises) { exercise in
                    Button(exercise.displayName) { onCommand(.selectExercise(exercise.id)) }
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .frame(width: 40, height: 40)
            }
            .tint(.white)
            .accessibilityLabel("Choose exercise")
            iconButton("stop.fill", label: "End workout", enabled: session.phase != .ended) {
                confirmingEnd = true
            }
            .confirmationDialog("End this workout?", isPresented: $confirmingEnd, titleVisibility: .visible) {
                Button("End Workout", role: .destructive) { onCommand(.endWorkout) }
                Button("Keep Going", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch session.phase {
        case .exercising:
            primary("Pause", systemImage: "pause.fill") { onCommand(.pause) }
        case .paused:
            primary("Resume", systemImage: "play.fill") { onCommand(.resume) }
        case .resting:
            primary("Start set \(session.currentSetNumber)", systemImage: "play.fill") { onCommand(.start) }
        case .framing, .ready:
            primary("Start", systemImage: "play.fill") { onCommand(.start) }
        case .choosingExercise, .changingExercise, .exerciseComplete, .ended:
            primary("Start", systemImage: "play.fill") {}
                .disabled(true)
        }
    }

    private func primary(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
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

    private var isSetInProgress: Bool {
        switch session.phase {
        case .exercising, .paused: return true
        default: return false
        }
    }

    private func setLabel(_ exercise: ExerciseDefinition) -> String {
        switch session.phase {
        case .resting: return "Next: set \(session.currentSetNumber) of \(exercise.sets)"
        case .exerciseComplete: return "All \(exercise.sets) sets done"
        default: return "Set \(session.currentSetNumber) of \(exercise.sets)"
        }
    }

    private func accessibilitySummary(_ exercise: ExerciseDefinition) -> String {
        "\(session.repCount) reps of \(exercise.targetLabel). \(setLabel(exercise))."
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
