import SwiftUI

/// Creates or edits a Saved Set: its name, and an ordered list of exercises with their own sets and reps.
/// The same exercise can appear more than once.
struct SavedSetEditorView: View {
    let isNew: Bool
    let catalog: [ExerciseDefinition]
    let onSave: (SavedExerciseSet) -> Void
    let onDelete: (SavedExerciseSet) -> Void
    let onDuplicate: (SavedExerciseSet) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: SavedExerciseSet
    @State private var confirmingDelete = false

    init(set: SavedExerciseSet, isNew: Bool, catalog: [ExerciseDefinition],
         onSave: @escaping (SavedExerciseSet) -> Void, onDelete: @escaping (SavedExerciseSet) -> Void,
         onDuplicate: @escaping (SavedExerciseSet) -> Void) {
        self.isNew = isNew
        self.catalog = catalog
        self.onSave = onSave
        self.onDelete = onDelete
        self.onDuplicate = onDuplicate
        _draft = State(initialValue: set)
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && !draft.items.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $draft.name)
                        .accessibilityIdentifier("savedSetNameField")
                }
                Section {
                    ForEach($draft.items) { $item in
                        SavedSetItemRow(item: $item, exercise: catalog.first { $0.id == item.exerciseID })
                    }
                    .onMove { draft.items.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { draft.items.remove(atOffsets: $0) }
                    Menu {
                        ForEach(catalog) { exercise in
                            Button(exercise.displayName) { draft.items.append(SavedExerciseSetItem(exercise: exercise)) }
                        }
                    } label: {
                        Label("Add Exercise", systemImage: "plus")
                    }
                    .accessibilityIdentifier("addSavedSetExerciseButton")
                } header: {
                    Text("Exercises")
                } footer: {
                    Text("Drag to reorder. The same exercise can appear more than once. These sets and reps apply only in this Saved Set.")
                }
                if !isNew {
                    Section {
                        Button {
                            onDuplicate(draft)
                            dismiss()
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Label("Delete Saved Set", systemImage: "trash")
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(isNew ? "New Saved Set" : "Edit Saved Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var saved = draft
                        saved.name = draft.name.trimmingCharacters(in: .whitespaces)
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("saveSavedSetButton")
                }
            }
            .confirmationDialog("Delete \(draft.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete Saved Set", role: .destructive) {
                    onDelete(draft)
                    dismiss()
                }
                Button("Keep It", role: .cancel) {}
            }
        }
    }
}

/// One exercise in the editor, with steppers for its sets and rep range.
private struct SavedSetItemRow: View {
    @Binding var item: SavedExerciseSetItem
    let exercise: ExerciseDefinition?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(exercise?.displayName ?? "Unavailable exercise")
                    .font(.headline)
                if exercise == nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Needs attention")
                }
                Spacer()
                Text(item.setsAndRepsLabel + (exercise?.perSide == true ? " each arm" : ""))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Stepper("Sets: \(item.setCount)", value: $item.setCount, in: 1...10)
            Stepper("Reps from: \(item.targetRepMinimum)", value: Binding(
                get: { item.targetRepMinimum },
                set: { item.targetRepMinimum = $0; item.targetRepMaximum = max(item.targetRepMaximum, $0) }), in: 1...50)
            Stepper("Reps to: \(item.targetRepMaximum)", value: Binding(
                get: { item.targetRepMaximum },
                set: { item.targetRepMaximum = $0; item.targetRepMinimum = min(item.targetRepMinimum, $0) }), in: 1...50)
        }
        .font(.subheadline)
        .padding(.vertical, 2)
    }
}

/// Adjusts an exercise's sets and reps from the list. The choice is remembered on this phone and can be
/// reset; the exercise's built-in default never changes.
struct ExerciseTargetEditor: View {
    let exercise: ExerciseDefinition
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var target: ExerciseTarget

    init(exercise: ExerciseDefinition, onChange: @escaping () -> Void) {
        self.exercise = exercise
        self.onChange = onChange
        _target = State(initialValue: ExerciseTargetStore.target(for: exercise.id) ?? ExerciseTarget(exercise))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Sets: \(target.sets)", value: $target.sets, in: 1...10)
                    Stepper("Reps from: \(target.repMinimum)", value: Binding(
                        get: { target.repMinimum },
                        set: { target.repMinimum = $0; target.repMaximum = max(target.repMaximum, $0) }), in: 1...50)
                    Stepper("Reps to: \(target.repMaximum)", value: Binding(
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
                        // Matching the default stores nothing, so future default changes still apply.
                        ExerciseTargetStore.setTarget(target == ExerciseTarget(exercise) ? nil : target, for: exercise.id)
                        onChange()
                        dismiss()
                    }
                }
            }
        }
    }
}
