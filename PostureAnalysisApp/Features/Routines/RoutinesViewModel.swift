import Foundation
import Observation

@MainActor
protocol RoutinesViewModeling: AnyObject, Observable {
    var state: RoutinesState { get }
    func send(_ intent: RoutinesIntent)
}

@MainActor
@Observable
final class RoutinesViewModel: RoutinesViewModeling {
    private(set) var state = RoutinesState(routines: [])

    private let routines: (any RoutineRepository)?
    private let exerciseCatalog: any ExerciseCatalogProviding
    private let router: AppRouter

    init(
        routines: (any RoutineRepository)?,
        exerciseCatalog: any ExerciseCatalogProviding,
        router: AppRouter
    ) {
        self.routines = routines
        self.exerciseCatalog = exerciseCatalog
        self.router = router
        refresh()
    }

    func send(_ intent: RoutinesIntent) {
        switch intent {
        case .appeared:
            refresh()
        case .open(let id):
            guard state.routines.contains(where: { $0.id == id }) else { return }
            router.open(.routine(id: id))
        case .start(let id):
            guard let routine = state.routines.first(where: { $0.id == id }), routine.canStart else { return }
            router.open(.workout(exerciseID: nil, routineID: id))
        case .createRoutine:
            router.open(.routineEditor(id: nil))
        case .edit(let id):
            guard state.routines.contains(where: { $0.id == id }) else { return }
            router.open(.routineEditor(id: id))
        case .duplicate(let id):
            guard let set = try? routines?.list().first(where: { $0.id == id }) else { return }
            _ = try? routines?.duplicate(set)
            refresh()
        case .requestDelete(let id):
            guard state.routines.contains(where: { $0.id == id }) else { return }
            state.deleteConfirmationRoutineID = id
        case .confirmDelete:
            guard let id = state.deleteConfirmationRoutineID else { return }
            do {
                try routines?.delete(id: id)
                state.deleteConfirmationRoutineID = nil
                refresh()
            } catch {
                // Keep the confirmation available so the user can retry.
            }
        case .cancelDelete:
            state.deleteConfirmationRoutineID = nil
        }
    }

    private func refresh() {
        let savedSets = (try? routines?.list()) ?? []
        state.routines = savedSets.map(makePresentation(for:))
        if let pendingID = state.deleteConfirmationRoutineID,
           !state.routines.contains(where: { $0.id == pendingID }) {
            state.deleteConfirmationRoutineID = nil
        }
    }

    private func makePresentation(for set: SavedExerciseSet) -> RoutineCardPresentation {
        let itemCount = set.items.count
        let setCount = set.items.reduce(0) { $0 + $1.setCount }
        let exerciseText = itemCount == 1 ? "1 exercise" : "\(itemCount) exercises"
        let setText = setCount == 1 ? "1 set" : "\(setCount) sets"
        let theme: RoutineTheme
        if let firstItem = set.items.first,
           let firstExercise = exerciseCatalog.exercise(firstItem.exerciseID) {
            theme = .exercise(firstExercise.presentation.gradient)
        } else {
            theme = .brand
        }
        let exerciseNames = set.items.map { item in
            exerciseCatalog.exercise(item.exerciseID)?.presentation.shortName ?? item.exerciseID.rawValue
        }

        return RoutineCardPresentation(
            id: set.id,
            name: set.name,
            summary: "\(exerciseText) · \(setText)",
            exerciseNames: exerciseNames,
            theme: theme,
            canStart: !set.plan(in: exerciseCatalog.all).items.isEmpty
        )
    }
}
