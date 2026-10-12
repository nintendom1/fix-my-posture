import SwiftData
import SwiftUI

/// The first Workout Coach screen, before the camera starts: Saved Sets and individual exercises.
/// Starting either opens the coach.
struct WorkoutSelectionView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case savedSets = "Saved Sets"
        case exercises = "Exercises"

        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedExerciseSetEntity.createdAt) private var savedSets: [SavedExerciseSetEntity]
    @State private var filter: Filter = .all
    @State private var launch: CoachLaunch?
    @State private var editing: SavedSetEditing?
    @State private var adjusting: ExerciseDefinition?
    /// Bumped after sets or reps are adjusted, so rows re-read the remembered targets.
    @State private var targetsVersion = 0
    var catalog: [ExerciseDefinition] = ExerciseCatalog.all

    /// The catalog with remembered sets and reps applied.
    private var exercises: [ExerciseDefinition] {
        _ = targetsVersion
        return ExerciseTargetStore.applying(to: catalog)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Show", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if filter != .exercises { savedSetsSection }
                if filter != .savedSets { exercisesSection }
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
            WorkoutCoachView(initialExercise: launch.exerciseID, plan: launch.plan)
        }
        .sheet(item: $editing) { editing in
            SavedSetEditorView(set: editing.savedSet, isNew: editing.isNew, catalog: catalog,
                               onSave: save, onDelete: delete, onDuplicate: duplicate)
        }
        .sheet(item: $adjusting) { exercise in
            ExerciseTargetEditor(exercise: exercise) { targetsVersion += 1 }
                .presentationDetents([.medium])
        }
    }

    private var savedSetsSection: some View {
        Section {
            ForEach(savedSets) { entity in
                let set = entity.value
                let missing = set.missingItems(in: catalog)
                HStack {
                    Button {
                        launch = CoachLaunch(exerciseID: nil, plan: set.plan(in: catalog))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(set.name)
                                .font(.headline)
                            Text(set.items.count == 1 ? "1 exercise" : "\(set.items.count) exercises")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if !missing.isEmpty {
                                Label("Needs attention: \(missing.count == 1 ? "an exercise is" : "some exercises are") unavailable",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(set.plan(in: catalog).items.isEmpty)
                    Button {
                        editing = SavedSetEditing(savedSet: set, isNew: false)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.body.weight(.semibold))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Edit \(set.name)")
                }
                .accessibilityIdentifier("savedSet_\(set.id.uuidString)")
            }
            Button {
                editing = SavedSetEditing(savedSet: SavedExerciseSet(name: "New Saved Set", items: []), isNew: true)
            } label: {
                Label("Create Saved Set", systemImage: "plus")
            }
            .accessibilityIdentifier("createSavedSetButton")
        } header: {
            Text("Saved Sets")
        } footer: {
            if savedSets.isEmpty {
                Text("A Saved Set runs several exercises in order, each with its own sets and reps.")
            }
        }
    }

    private var exercisesSection: some View {
        Section {
            ForEach(exercises) { exercise in
                HStack {
                    Button {
                        launch = CoachLaunch(exerciseID: exercise.id, plan: nil)
                    } label: {
                        Text(exercise.displayName)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("workoutExercise_\(exercise.id.rawValue)")
                    Button {
                        adjusting = catalog.first { $0.id == exercise.id }
                    } label: {
                        HStack(spacing: 4) {
                            Text(exercise.setsAndRepsLabel)
                                .font(.subheadline.monospacedDigit())
                            Image(systemName: "slider.horizontal.3")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(exercise.setsAndRepsLabel). Adjust sets and reps")
                }
            }
        } header: {
            Text("Exercises")
        } footer: {
            Text("Tap sets and reps to adjust them. Prop your phone up in portrait. Reps are counted with the front camera on this iPhone and never recorded.")
        }
    }

    private func save(_ set: SavedExerciseSet) {
        if let entity = savedSets.first(where: { $0.id == set.id }) {
            entity.update(from: set)
        } else {
            modelContext.insert(SavedExerciseSetEntity(set))
        }
        try? modelContext.save()
    }

    private func delete(_ set: SavedExerciseSet) {
        guard let entity = savedSets.first(where: { $0.id == set.id }) else { return }
        modelContext.delete(entity)
        try? modelContext.save()
    }

    private func duplicate(_ set: SavedExerciseSet) {
        modelContext.insert(SavedExerciseSetEntity(set.duplicated()))
        try? modelContext.save()
    }
}

private struct CoachLaunch: Identifiable {
    let id = UUID()
    let exerciseID: ExerciseID?
    let plan: WorkoutPlan?
}

private struct SavedSetEditing: Identifiable {
    let savedSet: SavedExerciseSet
    let isNew: Bool
    var id: UUID { savedSet.id }
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
            if let plan = session.plan, session.isFollowingPlan {
                Text("Choosing another exercise leaves \(plan.name); the rest of it is skipped. Cancel to stay in it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
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
