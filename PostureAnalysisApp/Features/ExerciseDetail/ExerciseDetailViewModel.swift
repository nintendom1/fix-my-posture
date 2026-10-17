import Foundation
import Observation

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
        state = Self.makeState(for: exercise, target: currentTarget)
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

    private static func makeState(for exercise: ExerciseDefinition, target: ExerciseTarget) -> ExerciseDetailState {
        ExerciseDetailState(
            id: exercise.id,
            name: exercise.displayName,
            muscles: exercise.presentation.muscles.joined(separator: " · "),
            gradient: exercise.presentation.gradient,
            symbolName: exercise.presentation.symbolName,
            equipmentText: exercise.presentation.equipmentLine,
            cameraSetupText: exercise.presentation.cameraSetupLine,
            watchesFor: exercise.presentation.watchesFor.map(\.text),
            steps: exercise.guide.steps,
            sets: target.sets,
            repMinimum: target.repMinimum,
            repMaximum: target.repMaximum
        )
    }
}
