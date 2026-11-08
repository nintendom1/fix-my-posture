import SwiftUI

/// Adjusts an exercise's sets and reps from the list. The choice is remembered on this phone and can be
/// reset; the exercise's built-in default never changes.
struct ExerciseTargetEditor: View {
    let exercise: ExerciseDefinition
    let preferences: any AppPreferencesStoring
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var target: ExerciseTarget

    init(exercise: ExerciseDefinition, preferences: any AppPreferencesStoring, onChange: @escaping () -> Void) {
        self.exercise = exercise
        self.preferences = preferences
        self.onChange = onChange
        _target = State(initialValue: ExerciseTargetStore.target(for: exercise.id, preferences: preferences) ?? ExerciseTarget(exercise))
    }

    /// Timed holds keep seconds in the rep fields.
    private var unit: String { exercise.doseUnit == .seconds ? "Seconds" : "Reps" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Sets: \(target.sets)", value: $target.sets, in: 1...10)
                    Stepper("\(unit) from: \(target.repMinimum)", value: Binding(
                        get: { target.repMinimum },
                        set: { target.repMinimum = $0; target.repMaximum = max(target.repMaximum, $0) }), in: 1...50)
                    Stepper("\(unit) to: \(target.repMaximum)", value: Binding(
                        get: { target.repMaximum },
                        set: { target.repMaximum = $0; target.repMinimum = min(target.repMinimum, $0) }), in: 1...50)
                } footer: {
                    Text("The set completes at the top of the range. Default: \(exercise.setsAndRepsLabel).")
                }
                Section {
                    Button("Reset to Default") { target = ExerciseTarget(exercise) }
                        .disabled(target == ExerciseTarget(exercise))
                }
            }
            .navigationTitle(exercise.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        ExerciseTargetStore.setTarget(target == ExerciseTarget(exercise) ? nil : target,
                                                      for: exercise.id, preferences: preferences)
                        onChange()
                        dismiss()
                    }
                }
            }
        }
    }
}
