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
    private let workoutHistory: (any WorkoutHistoryRepository)?
    private let exerciseCatalog: any ExerciseCatalogProviding
    private let preferences: any AppPreferencesStoring
    private let router: AppRouter
    private let reminderReconciliation: (any WorkoutReminderReconciliation)?
    private let now: () -> Date
    private let calendar: Calendar

    init(
        routines: (any RoutineRepository)?,
        workoutHistory: (any WorkoutHistoryRepository)?,
        exerciseCatalog: any ExerciseCatalogProviding,
        preferences: any AppPreferencesStoring,
        router: AppRouter,
        reminderReconciliation: (any WorkoutReminderReconciliation)? = nil,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.routines = routines
        self.workoutHistory = workoutHistory
        self.exerciseCatalog = exerciseCatalog
        self.preferences = preferences
        self.router = router
        self.reminderReconciliation = reminderReconciliation
        self.now = now
        self.calendar = calendar
        refresh()
    }

    func send(_ intent: RoutinesIntent) {
        switch intent {
        case .appeared:
            refresh()
        case .open(let id):
            guard state.allRoutines.contains(where: { $0.id == id }) else { return }
            router.open(.routine(id: id))
        case .start(let id):
            guard let routine = state.allRoutines.first(where: { $0.id == id }), routine.canStart else { return }
            router.open(.workout(exerciseID: nil, routineID: id))
        case .createRoutine:
            router.open(.routineEditor(id: nil))
        case .edit(let id):
            guard state.allRoutines.contains(where: { $0.id == id }) else { return }
            router.open(.routineEditor(id: id))
        case .duplicate(let id):
            guard !BuiltInRoutines.contains(id: id) else { return }
            guard let set = try? routines?.list().first(where: { $0.id == id }) else { return }
            do {
                _ = try routines?.duplicate(set)
                reminderReconciliation?.reconcile()
                refresh()
            } catch {
                // Leave the list unchanged when duplication fails.
            }
        case .requestDelete(let id):
            guard let routine = state.allRoutines.first(where: { $0.id == id }), !routine.isBuiltIn else { return }
            state.deleteConfirmationRoutineID = id
        case .confirmDelete:
            guard let id = state.deleteConfirmationRoutineID else { return }
            guard !BuiltInRoutines.contains(id: id) else {
                state.deleteConfirmationRoutineID = nil
                return
            }
            do {
                try routines?.delete(id: id)
                state.deleteConfirmationRoutineID = nil
                reminderReconciliation?.reconcile()
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
        let records = (try? workoutHistory?.list()) ?? []
        let presentations = savedSets.map { makePresentation(for: $0, records: records) }
        state.routines = presentations.filter { !$0.isBuiltIn }
        state.starterRoutines = presentations.filter(\.isBuiltIn)
        if let pendingID = state.deleteConfirmationRoutineID,
           !state.allRoutines.contains(where: { $0.id == pendingID }) || BuiltInRoutines.contains(id: pendingID) {
            state.deleteConfirmationRoutineID = nil
        }
    }

    private func makePresentation(for set: SavedExerciseSet, records: [WorkoutRecord]) -> RoutineCardPresentation {
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
        let lastDoneLabel = RoutineRotation.lastDone(routine: set, records: records).map {
            LastDoneFormatter.routineLabel(for: $0, now: now(), calendar: calendar)
        }
        let estimatedMinutes = RoutineEstimator.minutes(
            for: set,
            exercises: exerciseCatalog.all,
            restPolicy: preferences.restPolicy
        )

        return RoutineCardPresentation(
            id: set.id,
            name: set.name,
            summary: "\(exerciseText) · \(setText) · about \(estimatedMinutes) min",
            lastDoneLabel: lastDoneLabel,
            exerciseNames: exerciseNames,
            theme: theme,
            canStart: !set.plan(in: exerciseCatalog.all).items.isEmpty,
            isBuiltIn: BuiltInRoutines.contains(id: set.id)
        )
    }
}
