import SwiftUI

/// Shown when every set of the exercise is done: this round's reps, then what to do next.
struct ExerciseCompleteCard: View {
    let session: WorkoutSession
    let onAnotherRound: () -> Void
    let onChooseExercise: () -> Void
    let onEndWorkout: () -> Void

    var body: some View {
        if let exercise = session.exercise {
            let record = session.progress[exercise.id] ?? ExerciseProgress()
            let sets = record.roundSetReps
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(WorkoutJointOverlayView.endPositionColor)
                    .accessibilityHidden(true)
                Text("\(exercise.displayName) complete")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                VStack(spacing: 4) {
                    if record.round > 1 {
                        Text("Round \(record.round)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(sets.enumerated().map { "Set \($0.offset + 1): \($0.element)" }.joined(separator: " · "))
                        .font(.headline.monospacedDigit())
                    Text("\(sets.reduce(0, +)) reps")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let workoutLine {
                        Text(workoutLine)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .accessibilityElement(children: .combine)

                VStack(spacing: 8) {
                    button("Another Round", systemImage: "arrow.clockwise", prominent: true, action: onAnotherRound)
                        .accessibilityIdentifier("anotherRoundButton")
                    if session.exercises.count > 1 {
                        button("Choose Exercise", systemImage: "list.bullet", prominent: false, action: onChooseExercise)
                            .accessibilityIdentifier("chooseExerciseButton")
                    }
                    button("End Workout", systemImage: "flag.checkered", prominent: false, action: onEndWorkout)
                        .accessibilityIdentifier("completeEndWorkoutButton")
                }
                .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: 360)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(24)
            .environment(\.colorScheme, .dark)
        }
    }

    /// Everything finished in this workout, when more than this exercise's round.
    private var workoutLine: String? {
        let finished = session.exercises.compactMap { exercise -> (String, Int)? in
            let sets = session.progress[exercise.id]?.setReps.count ?? 0
            return sets > 0 ? (exercise.displayName, sets) : nil
        }
        let total = finished.map(\.1).reduce(0, +)
        guard let current = session.exercise, total > session.completedSets(for: current.id) else { return nil }
        return "This workout: " + finished.map { "\($0.0) \($0.1 == 1 ? "1 set" : "\($0.1) sets")" }.joined(separator: " · ")
    }

    private func button(_ title: String, systemImage: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(prominent ? AnyPrimitiveButtonStyle(.borderedProminent) : AnyPrimitiveButtonStyle(.bordered))
        .tint(prominent ? .blue : .white)
    }
}

/// Lets one call site pick between button styles.
private struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: PrimitiveButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}
