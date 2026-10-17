import Foundation
import Observation

@MainActor
protocol RoutineDetailViewModeling: AnyObject, Observable {
    var state: RoutineDetailState { get }
    func send(_ intent: RoutineDetailIntent)
}

@MainActor
@Observable
final class RoutineDetailViewModel: RoutineDetailViewModeling {
    private(set) var state = RoutineDetailState(routine: nil)

    private let id: UUID
    private let routines: (any RoutineRepository)?
    private let workoutHistory: (any WorkoutHistoryRepository)?
    private let exerciseCatalog: any ExerciseCatalogProviding
    private let router: AppRouter

    init(
        id: UUID,
        routines: (any RoutineRepository)?,
        workoutHistory: (any WorkoutHistoryRepository)?,
        exerciseCatalog: any ExerciseCatalogProviding,
        router: AppRouter
    ) {
        self.id = id
        self.routines = routines
        self.workoutHistory = workoutHistory
        self.exerciseCatalog = exerciseCatalog
        self.router = router
        refresh()
    }

    func send(_ intent: RoutineDetailIntent) {
        switch intent {
        case .appeared:
            refresh()
        case .back:
            popToRoutines()
        case .edit:
            guard let routine = state.routine else { return }
            router.open(.routineEditor(id: routine.id))
        case .duplicate:
            guard let routine = state.routine,
                  let set = try? routines?.list().first(where: { $0.id == routine.id }) else { return }
            _ = try? routines?.duplicate(set)
        case .requestDelete:
            guard state.routine != nil else { return }
            state.showsDeleteConfirmation = true
        case .confirmDelete:
            guard state.showsDeleteConfirmation, state.routine != nil else { return }
            do {
                try routines?.delete(id: id)
                state.showsDeleteConfirmation = false
                state.routine = nil
                popToRoutines()
            } catch {
                // Keep the confirmation available so the user can retry.
            }
        case .cancelDelete:
            state.showsDeleteConfirmation = false
        case .start:
            guard let routine = state.routine, routine.canStart else { return }
            router.open(.workout(exerciseID: nil, routineID: routine.id))
        }
    }

    private func refresh() {
        guard let set = try? routines?.list().first(where: { $0.id == id }) else {
            state.routine = nil
            return
        }
        let setCount = set.items.reduce(0) { $0 + $1.setCount }
        let itemCount = set.items.count
        let exerciseText = itemCount == 1 ? "1 exercise" : "\(itemCount) exercises"
        let setText = setCount == 1 ? "1 set" : "\(setCount) sets"
        let weights = lastKnownWeights(for: set)
        let steps = set.items.enumerated().compactMap { index, item -> RoutineStepPresentation? in
            guard let exercise = exerciseCatalog.exercise(item.exerciseID) else { return nil }
            let perSide = exercise.perSide ? " / side" : ""
            let target = "\(item.setsAndRepsLabel)\(perSide)"
            let camera: String
            switch exercise.cameraView {
            case .front: camera = "Front camera"
            case .side: camera = "Side camera"
            case .floor: camera = "Floor camera"
            }
            return RoutineStepPresentation(
                id: item.id,
                number: index + 1,
                exerciseID: exercise.id,
                name: exercise.presentation.shortName,
                target: target,
                weight: weights[index],
                camera: camera,
                gradient: exercise.presentation.gradient
            )
        }
        state.routine = RoutineDetailPresentation(
            id: set.id,
            name: set.name,
            summary: "\(exerciseText) · \(setText)",
            steps: steps,
            canStart: !set.plan(in: exerciseCatalog.all).items.isEmpty
        )
    }

    private func lastKnownWeights(for set: SavedExerciseSet) -> [Int: String] {
        guard let record = (try? workoutHistory?.list())?.filter({ $0.planID == set.id }).max(by: {
            $0.endedAt < $1.endedAt
        }) else { return [:] }

        var entriesByExercise: [ExerciseID: [WorkoutRecordEntry]] = [:]
        for entry in record.entries {
            entriesByExercise[entry.exerciseID, default: []].append(entry)
        }
        var result: [Int: String] = [:]
        for (index, item) in set.items.enumerated() {
            guard var entries = entriesByExercise[item.exerciseID], !entries.isEmpty else { continue }
            let entry = entries.removeFirst()
            entriesByExercise[item.exerciseID] = entries
            if let label = entry.sets.reversed().compactMap({ $0.weight?.label }).first {
                result[index] = label
            }
        }
        return result
    }

    private func popToRoutines() {
        let path = router.path(for: .routines)
        if !path.isEmpty {
            router.setPath(Array(path.dropLast()), for: .routines)
        }
        router.selectedTab = .routines
    }
}
