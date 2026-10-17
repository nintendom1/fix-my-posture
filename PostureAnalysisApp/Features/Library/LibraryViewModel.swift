import Foundation
import Observation

@MainActor
protocol LibraryViewModeling: AnyObject, Observable {
    var state: LibraryState { get }
    func send(_ intent: LibraryIntent)
}

@MainActor
@Observable
final class LibraryViewModel: LibraryViewModeling {
    private(set) var state = LibraryState()

    private let workoutHistory: (any WorkoutHistoryRepository)?
    private let exerciseCatalog: any ExerciseCatalogProviding
    private let preferences: any AppPreferencesStoring
    private let router: AppRouter

    init(
        workoutHistory: (any WorkoutHistoryRepository)?,
        exerciseCatalog: any ExerciseCatalogProviding,
        preferences: any AppPreferencesStoring,
        router: AppRouter
    ) {
        self.workoutHistory = workoutHistory
        self.exerciseCatalog = exerciseCatalog
        self.preferences = preferences
        self.router = router
        refresh()
    }

    func send(_ intent: LibraryIntent) {
        switch intent {
        case .appeared:
            refresh()
        case .back:
            popLibrary()
        case .exerciseSelected(let id):
            guard exerciseCatalog.exercise(id) != nil else { return }
            router.open(.exercise(id: id))
        }
    }

    private func refresh() {
        let weights = latestWeights()
        let exercises = ExerciseTargetStore.applying(to: exerciseCatalog.all, preferences: preferences)
        let groups: [(String, ExerciseFilterGroup)] = [
            ("Upper body", .upper),
            ("Lower body", .lower)
        ]
        state.groups = groups.map { title, filter in
            LibraryExerciseGroup(
                title: title,
                exercises: exercises.compactMap { exercise in
                    guard exercise.presentation.filterGroups.contains(filter) else { return nil }
                    return LibraryExerciseRow(
                        id: exercise.id,
                        name: libraryName(for: exercise),
                        muscles: exercise.presentation.muscles.joined(separator: " · "),
                        target: "\(exercise.sets) × \(exercise.targetLabel)" + (exercise.perSide ? " / side" : ""),
                        weight: weights[exercise.id],
                        equipment: exercise.presentation.equipmentLine,
                        cameraSetup: exercise.presentation.cameraSetupLine,
                        gradient: exercise.presentation.gradient,
                        symbolName: exercise.presentation.symbolName
                    )
                }
            )
        }
    }

    private func latestWeights() -> [ExerciseID: String] {
        let records = (try? workoutHistory?.list()) ?? []
        var weights: [ExerciseID: String] = [:]
        for record in records.sorted(by: { $0.endedAt > $1.endedAt }) {
            for entry in record.entries where weights[entry.exerciseID] == nil {
                if let label = entry.sets.reversed().compactMap({ $0.weight?.label }).first {
                    weights[entry.exerciseID] = label
                }
            }
        }
        return weights
    }

    private func libraryName(for exercise: ExerciseDefinition) -> String {
        switch exercise.id {
        case .shoulderPress: return "Dumbbell Shoulder Press"
        case .hammerCurl: return "Hammer Curl"
        case .tricepsExtension: return "Triceps Extension"
        case .dumbbellRow: return "Dumbbell Row"
        case .airSquat: return "Air Squat"
        case .pushUp: return "Push-Up"
        default: return exercise.displayName
        }
    }

    private func popLibrary() {
        let path = router.path(for: .train)
        if !path.isEmpty {
            router.setPath(Array(path.dropLast()), for: .train)
        }
        router.selectedTab = .train
    }
}
