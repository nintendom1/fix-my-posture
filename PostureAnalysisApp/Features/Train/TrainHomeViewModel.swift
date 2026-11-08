import AdaptiveTraining
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
    private let todaySession: (any TodaySessionHeroProviding)?
    private let reminderReconciliation: (any WorkoutReminderReconciliation)?
    private let now: () -> Date
    private let calendar: Calendar

    private static let quickStartOrder: [ExerciseID] = [
        .shoulderPress, .airSquat, .dumbbellRow, .pushUp
    ]

    init(
        routines: (any RoutineRepository)?,
        workoutHistory: (any WorkoutHistoryRepository)?,
        exerciseCatalog: any ExerciseCatalogProviding,
        preferences: any AppPreferencesStoring,
        router: AppRouter,
        todaySession: (any TodaySessionHeroProviding)? = nil,
        reminderReconciliation: (any WorkoutReminderReconciliation)? = nil,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.routines = routines
        self.workoutHistory = workoutHistory
        self.exerciseCatalog = exerciseCatalog
        self.preferences = preferences
        self.router = router
        self.todaySession = todaySession
        self.reminderReconciliation = reminderReconciliation
        self.now = now
        self.calendar = calendar
        state = TrainHomeState(
            dateLabel: TrainHomeDateFormatter.label(now()),
            heroRoutine: nil,
            routineChoices: [],
            isRoutinePickerPresented: false,
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
        case .startTodaySession:
            guard let todaySession else { return }
            guard todaySession.start(asOf: now()) != nil else {
                var hero = state.todayHero
                hero?.startProblem = todaySession.lastStartProblem ?? "Today's Session couldn't start."
                state.todayHero = hero
                return
            }
            router.open(.todaySession)
        case .findStartingPoint:
            router.open(.calibration)
        case .pickAnother:
            state.isRoutinePickerPresented = true
        case .selectRoutine(let id):
            guard state.routineChoices.contains(where: { $0.id == id }) else { return }
            preferences.upNextOverride = id
            reminderReconciliation?.reconcile()
            state.isRoutinePickerPresented = false
            refresh()
        case .dismissRoutinePicker:
            state.isRoutinePickerPresented = false
        case .startExercise(let id):
            guard exerciseCatalog.exercise(id) != nil else { return }
            router.open(.workout(exerciseID: id, routineID: nil))
        case .createRoutine:
            router.open(.routineEditor(id: nil))
        case .openSettings:
            router.open(.settings)
        case .dismissPersonaIntro:
            preferences.personaIntroCardDismissed = true
            state.showsPersonaIntro = false
        case .openPersonaSettings:
            router.present(.settings)
        case .openLibrary:
            router.open(.library)
        case .openHistory:
            router.open(.history)
        }
    }

    private func refresh() {
        let currentDate = now()
        let savedRoutines = (try? routines?.listWithUpdateDates()) ?? []
        let history: [WorkoutRecord]
        if let workoutHistory {
            history = (try? workoutHistory.list()) ?? []
        } else {
            history = []
        }
        let choices = savedRoutines
            .map { makeHero(for: $0.set, records: history) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let upNext = CurrentUpNextRoutine.select(
            routines: savedRoutines,
            records: history,
            override: preferences.upNextOverride,
            catalog: exerciseCatalog.all
        )
        let heroSet = upNext ?? savedRoutines.first(where: { !$0.set.plan(in: exerciseCatalog.all).items.isEmpty })?.set
        state = TrainHomeState(
            dateLabel: TrainHomeDateFormatter.label(currentDate),
            heroRoutine: heroSet.map { makeHero(for: $0, records: history) },
            routineChoices: choices,
            isRoutinePickerPresented: state.isRoutinePickerPresented,
            exercises: makeExerciseTiles(),
            lastWorkout: history.first.map(makeLastWorkout),
            showsPersonaIntro: shouldShowPersonaIntro,
            todayHero: todaySession.flatMap { makeTodayHero(from: $0.status(asOf: currentDate)) }
        )
    }

    private func makeTodayHero(from status: TodaySessionStatus) -> TrainTodayHeroPresentation? {
        switch status {
        case .ready(let session):
            let amount = session.main.dose
            let doseText = amount.kind == .reps ? "× \(amount.amount)" : "for \(amount.amount) s"
            let minutes = Self.roundedMinutes(session.estimatedSeconds)
            return TrainTodayHeroPresentation(
                kind: .ready,
                eyebrow: "TODAY'S SESSION",
                title: CalibrationCopy.areaName(session.family),
                subtitle: "\(todaySession?.displayName(of: session.main.variant) ?? session.main.variant.rawValue) \(doseText) · about \(minutes) min",
                action: .startTodaySession,
                actionTitle: "Start"
            )
        case .completedToday(_, let next):
            let subtitle = next.map { "Next time: \(CalibrationCopy.areaName($0.family))" } ?? "Nice work."
            return TrainTodayHeroPresentation(
                kind: .completed,
                eyebrow: "TODAY'S SESSION",
                title: "Done for today",
                subtitle: subtitle,
                action: nil,
                actionTitle: nil
            )
        case .needsCalibration:
            return TrainTodayHeroPresentation(
                kind: .needsCalibration,
                eyebrow: "ADAPTIVE TRAINING",
                title: "Find your starting point",
                subtitle: "A few tiny samples, then a short session each day.",
                action: .findStartingPoint,
                actionTitle: "Find your starting point"
            )
        case .nothingOffered:
            return nil
        }
    }

    private static func roundedMinutes(_ seconds: Int) -> Int {
        let nonnegativeSeconds = max(0, seconds)
        let rounded = nonnegativeSeconds / 60 + (nonnegativeSeconds % 60 >= 30 ? 1 : 0)
        return max(1, rounded)
    }

    private var shouldShowPersonaIntro: Bool {
        let reminderSettings = preferences.workoutReminderSettings
        return reminderSettings.enabled
            && reminderSettings.style == .character
            && preferences.extraPersonableEnabled
            && !preferences.personaIntroCardDismissed
    }

    private func makeHero(for set: SavedExerciseSet, records: [WorkoutRecord]) -> TrainHomeRoutinePresentation {
        let chips = set.items.prefix(3).map { item in
            chipName(for: item.exerciseID)
        } + (set.items.count > 3 ? ["+\(set.items.count - 3)"] : [])

        return TrainHomeRoutinePresentation(
            id: set.id,
            name: set.name,
            exerciseCount: set.items.count,
            setCount: set.items.reduce(0) { $0 + $1.setCount },
            estimatedMinutes: RoutineEstimator.minutes(
                for: set,
                exercises: exerciseCatalog.all,
                restPolicy: preferences.restPolicy
            ),
            lastDoneLabel: RoutineRotation.lastDone(routine: set, records: records).map {
                LastDoneFormatter.heroLabel(for: $0, now: now(), calendar: calendar)
            },
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
            return TrainExerciseTile(
                id: exercise.id,
                name: exercise.presentation.shortName,
                target: "\(exercise.sets) × \(exercise.targetLabel)\(exercise.perSideTargetSuffix)",
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
