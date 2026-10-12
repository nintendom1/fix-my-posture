import SwiftUI

/// The first Workout Coach screen: every exercise, before the camera starts. Choosing one opens the coach.
struct WorkoutSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var launch: CoachLaunch?
    var exercises: [ExerciseDefinition] = ExerciseCatalog.all

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(exercises) { exercise in
                        Button {
                            launch = CoachLaunch(exerciseID: exercise.id)
                        } label: {
                            HStack {
                                ExerciseSummaryLabel(exercise: exercise)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("workoutExercise_\(exercise.id.rawValue)")
                    }
                } header: {
                    Text("Exercises")
                } footer: {
                    Text("Prop your phone up in portrait. Reps are counted with the front camera on this iPhone and never recorded.")
                }
            }
            .navigationTitle("Workout Coach")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("closeWorkoutSelectionButton")
                }
            }
        }
        .fullScreenCover(item: $launch) { launch in
            WorkoutCoachView(initialExercise: launch.exerciseID)
        }
    }
}

private struct CoachLaunch: Identifiable {
    let id = UUID()
    let exerciseID: ExerciseID
}

/// An exercise's name and its sets × reps target.
struct ExerciseSummaryLabel: View {
    let exercise: ExerciseDefinition
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.displayName)
                .font(.headline)
            Text(detail ?? "\(exercise.sets) sets × \(exercise.targetLabel) reps")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Mid-workout exercise chooser over the camera, for "change exercise". Picking one switches;
/// Cancel returns to where you were.
struct ExerciseChooserOverlay: View {
    let session: WorkoutSession
    let voiceActive: Bool
    let onSelect: (ExerciseID) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Choose an exercise")
                .font(.title3.bold())
            ForEach(session.exercises) { exercise in
                Button { onSelect(exercise.id) } label: {
                    HStack {
                        ExerciseSummaryLabel(exercise: exercise, detail: detail(for: exercise))
                        Spacer()
                        if exercise.id == session.exerciseID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(WorkoutJointOverlayView.endPositionColor)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chooseExercise_\(exercise.id.rawValue)")
            }
            if voiceActive {
                Text("Say an exercise name, or \u{201C}cancel\u{201D}.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("cancelChooseExerciseButton")
        }
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(24)
        .environment(\.colorScheme, .dark)
    }

    private func detail(for exercise: ExerciseDefinition) -> String {
        let done = session.setsDone(for: exercise)
        let target = "\(exercise.sets) sets × \(exercise.targetLabel) reps"
        guard done > 0 else { return target }
        return done >= exercise.sets ? "All \(exercise.sets) sets done" : "\(target) · \(done) done"
    }
}
