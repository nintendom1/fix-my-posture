import Foundation
import Observation

/// Resolves detail content without a live camera stance; Auto uses the exercise's usual view.
func exerciseDetailDefinition(for exercise: ExerciseDefinition,
                              preference: ExerciseViewPreference) -> ExerciseDefinition {
    guard exercise.hasViewChoice else { return exercise }
    let view: ExerciseCameraView
    switch preference {
    case .auto:
        view = exercise.usualView
    case .locked(let stance):
        view = exercise.view(for: stance) ?? exercise.usualView
    }
    return exercise.inView(view)
}

@MainActor
protocol ExerciseDetailViewModeling: AnyObject, Observable {
    var state: ExerciseDetailState { get }
    func send(_ intent: ExerciseDetailIntent)
}

@MainActor
@Observable
final class ExerciseDetailViewModel: ExerciseDetailViewModeling {
    private(set) var state: ExerciseDetailState

    private let id: ExerciseID
    private let exerciseCatalog: any ExerciseCatalogProviding
    private let preferences: any AppPreferencesStoring
    private let router: AppRouter
    private var target: ExerciseTarget?

    init(
        id: ExerciseID,
        exerciseCatalog: any ExerciseCatalogProviding,
        preferences: any AppPreferencesStoring,
        router: AppRouter
    ) {
        self.id = id
        self.exerciseCatalog = exerciseCatalog
        self.preferences = preferences
        self.router = router
        guard let exercise = exerciseCatalog.exercise(id) else {
            state = .unavailable(id: id)
            return
        }
        var currentTarget = ExerciseTargetStore.target(for: id, preferences: preferences) ?? ExerciseTarget(exercise)
        currentTarget.sets = min(10, max(1, currentTarget.sets))
        target = currentTarget
        let viewPreference = exercise.hasViewChoice ? preferences.viewPreference(for: id) : .auto
        let detailExercise = exerciseDetailDefinition(for: exercise, preference: viewPreference)
        state = Self.makeState(for: detailExercise, target: currentTarget, viewPreference: viewPreference)
    }

    func send(_ intent: ExerciseDetailIntent) {
        switch intent {
        case .appeared:
            refreshTarget()
        case .back:
            popExercise()
        case .decrementSets:
            changeSets(by: -1)
        case .incrementSets:
            changeSets(by: 1)
        case .cameraViewSelected(let preference):
            setCameraViewPreference(preference)
        case .editReps:
            guard state.isAvailable else { return }
            state.isTargetEditorPresented = true
        case .targetEditorDismissed:
            state.isTargetEditorPresented = false
            refreshTarget()
        case .watchGuide:
            guard state.isAvailable else { return }
            state.isGuidePresented = true
        case .dismissGuide:
            state.isGuidePresented = false
        case .startFromGuide:
            state.isGuidePresented = false
            startExercise()
        case .startExercise:
            startExercise()
        }
    }

    private func changeSets(by delta: Int) {
        guard let exercise = exerciseCatalog.exercise(id) else { return }
        var updated = target ?? ExerciseTargetStore.target(for: id, preferences: preferences) ?? ExerciseTarget(exercise)
        updated.sets = min(10, max(1, updated.sets + delta))
        target = updated
        state.sets = updated.sets
        persistTarget(updated, defaults: ExerciseTarget(exercise))
    }

    private func refreshTarget() {
        guard let exercise = exerciseCatalog.exercise(id) else { return }
        let currentTarget = ExerciseTargetStore.target(for: id, preferences: preferences) ?? ExerciseTarget(exercise)
        target = currentTarget
        state.sets = currentTarget.sets
        state.repMinimum = currentTarget.repMinimum
        state.repMaximum = currentTarget.repMaximum
        refreshViewPreference(for: exercise)
    }

    private func setCameraViewPreference(_ preference: ExerciseViewPreference) {
        guard let exercise = exerciseCatalog.exercise(id), exercise.hasViewChoice else { return }
        preferences.setViewPreference(preference, for: id)
        applyViewPreference(preference, for: exercise)
    }

    private func refreshViewPreference(for exercise: ExerciseDefinition) {
        let preference = exercise.hasViewChoice ? preferences.viewPreference(for: id) : .auto
        applyViewPreference(preference, for: exercise)
    }

    private func applyViewPreference(_ preference: ExerciseViewPreference, for exercise: ExerciseDefinition) {
        state.viewPreference = preference
        state.cameraSetupText = Self.cameraSetupText(for: exercise, preference: preference)
        state.steps = exerciseDetailDefinition(for: exercise, preference: preference).guide.steps
    }

    private static func cameraSetupText(for exercise: ExerciseDefinition,
                                        preference: ExerciseViewPreference) -> String {
        guard exercise.hasViewChoice else { return exercise.presentation.cameraSetupLine }
        switch preference {
        case .auto: return "Auto"
        case .locked(.facing): return "Front"
        case .locked(.sideOn): return "Side-on"
        }
    }

    private func persistTarget(_ target: ExerciseTarget, defaults: ExerciseTarget) {
        ExerciseTargetStore.setTarget(target == defaults ? nil : target, for: id, preferences: preferences)
    }

    private func startExercise() {
        guard state.isAvailable else { return }
        router.open(.workout(exerciseID: id, routineID: nil))
    }

    private func popExercise() {
        let path = router.path(for: .train)
        if !path.isEmpty {
            router.setPath(Array(path.dropLast()), for: .train)
        }
        router.selectedTab = .train
    }

    private static func makeState(for exercise: ExerciseDefinition,
                                  target: ExerciseTarget,
                                  viewPreference: ExerciseViewPreference) -> ExerciseDetailState {
        ExerciseDetailState(
            id: exercise.id,
            name: exercise.displayName,
            muscles: exercise.presentation.muscles.joined(separator: " · "),
            gradient: exercise.presentation.gradient,
            symbolName: exercise.presentation.symbolName,
            equipmentText: exercise.presentation.equipmentLine,
            cameraSetupText: cameraSetupText(for: exercise, preference: viewPreference),
            hasViewChoice: exercise.hasViewChoice,
            viewPreference: viewPreference,
            watchesFor: exercise.presentation.watchesFor.map(\.text),
            steps: exercise.guide.steps,
            sets: target.sets,
            repMinimum: target.repMinimum,
            repMaximum: target.repMaximum
        )
    }
}
