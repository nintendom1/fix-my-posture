import Foundation
import Observation

@MainActor
protocol TrainHomeViewModeling: AnyObject, Observable {
    var state: TrainHomeState { get }
    func send(_ intent: TrainHomeIntent)
}

@MainActor
@Observable
final class TrainHomeViewModel: TrainHomeViewModeling {
    private(set) var state: TrainHomeState

    private let routines: (any RoutineRepository)?
    private let workoutHistory: (any WorkoutHistoryRepository)?
    private let exerciseCatalog: any ExerciseCatalogProviding
    private let preferences: any AppPreferencesStoring
    private let router: AppRouter
    private let now: () -> Date

    private static let quickStartOrder: [ExerciseID] = [
        .shoulderPress, .airSquat, .dumbbellRow, .pushUp
    ]

    init(
        routines: (any RoutineRepository)?,
        workoutHistory: (any WorkoutHistoryRepository)?,
        exerciseCatalog: any ExerciseCatalogProviding,
        preferences: any AppPreferencesStoring,
        router: AppRouter,
        now: @escaping () -> Date = Date.init
    ) {
        self.routines = routines
        self.workoutHistory = workoutHistory
        self.exerciseCatalog = exerciseCatalog
        self.preferences = preferences
        self.router = router
        self.now = now
        state = TrainHomeState(
            dateLabel: TrainHomeDateFormatter.label(now()),
            heroRoutine: nil,
            exercises: [],
            lastWorkout: nil
        )
        refresh()
    }

    func send(_ intent: TrainHomeIntent) {
        switch intent {
        case .appeared:
            refresh()
        case .startRoutine:
            guard let routine = state.heroRoutine, routine.canStart else { return }
            router.open(.workout(exerciseID: nil, routineID: routine.id))
        case .startExercise(let id):
            guard exerciseCatalog.exercise(id) != nil else { return }
            router.open(.workout(exerciseID: id, routineID: nil))
        case .createRoutine:
            router.open(.routineEditor(id: nil))
        case .openSettings:
            router.open(.settings)
        case .openLibrary:
            router.open(.library)
        case .openHistory:
            router.open(.history)
        }
    }

    private func refresh() {
        let records = (try? routines?.listWithUpdateDates()) ?? []
        let mostRecentlyUpdated = records.max { $0.updatedAt < $1.updatedAt }
        let history: [WorkoutRecord]
        if let workoutHistory {
            history = (try? workoutHistory.list()) ?? []
        } else {
            history = []
        }
        state = TrainHomeState(
            dateLabel: TrainHomeDateFormatter.label(now()),
            heroRoutine: mostRecentlyUpdated.map { makeHero(for: $0.set) },
            exercises: makeExerciseTiles(),
            lastWorkout: history.first.map(makeLastWorkout)
        )
    }

    private func makeHero(for set: SavedExerciseSet) -> TrainHomeRoutinePresentation {
        let chips = set.items.prefix(3).map { item in
            chipName(for: item.exerciseID)
        } + (set.items.count > 3 ? ["+\(set.items.count - 3)"] : [])

        return TrainHomeRoutinePresentation(
            id: set.id,
            name: set.name,
            exerciseCount: set.items.count,
            setCount: set.items.reduce(0) { $0 + $1.setCount },
            estimatedMinutes: nil,
            chips: chips,
            canStart: !set.plan(in: exerciseCatalog.all).items.isEmpty
        )
    }

    private func chipName(for id: ExerciseID) -> String {
        guard let exercise = exerciseCatalog.exercise(id) else { return id.rawValue }
        return exercise.presentation.shortName.replacingOccurrences(of: "Dumbbell ", with: "")
    }

    private func makeExerciseTiles() -> [TrainExerciseTile] {
        let ordered = Self.quickStartOrder.compactMap { exerciseCatalog.exercise($0) }
        return ExerciseTargetStore.applying(to: ordered, preferences: preferences).map { exercise in
            let side = exercise.perSide ? " / side" : ""
            return TrainExerciseTile(
                id: exercise.id,
                name: exercise.presentation.shortName,
                target: "\(exercise.sets) × \(exercise.targetLabel)\(side)",
                gradient: exercise.presentation.gradient,
                symbolName: exercise.presentation.symbolName
            )
        }
    }

    private func makeLastWorkout(_ record: WorkoutRecord) -> TrainLastWorkoutPresentation {
        let duration = max(1, Int((record.endedAt.timeIntervalSince(record.startedAt) / 60).rounded()))
        let name = record.planName ?? record.entries.first?.name ?? "Workout"
        return TrainLastWorkoutPresentation(
            dateLabel: "Last workout · \(TrainHomeDateFormatter.weekday(record.startedAt))",
            summary: "\(name) · \(duration) min · \(record.totalReps) reps"
        )
    }
}
