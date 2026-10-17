import Foundation

enum WorkoutReminderRecommendation {
    case routine(SavedExerciseSet)
    case exercise(ExerciseDefinition)

    var target: WorkoutReminderTarget {
        switch self {
        case .routine(let routine): .routine(routine.id)
        case .exercise(let exercise): .exercise(exercise.id)
        }
    }
}

enum WorkoutReminderRecommendationSelector {
    static func select(
        routines: [SavedExerciseSetRecord],
        records: [WorkoutRecord],
        override: UUID?,
        exerciseCatalog: any ExerciseCatalogProviding,
        preferences: any AppPreferencesStoring
    ) -> WorkoutReminderRecommendation? {
        if let routine = CurrentUpNextRoutine.select(
            routines: routines,
            records: records,
            override: override,
            catalog: exerciseCatalog.all
        ) {
            return .routine(routine)
        }

        let exercises = ExerciseTargetStore.applying(to: exerciseCatalog.all, preferences: preferences)
        guard !exercises.isEmpty else { return nil }

        var mostRecentPerformed: [ExerciseID: Date] = [:]
        for record in records {
            for entry in record.entries where entry.outcome != .skipped && !entry.sets.isEmpty {
                if let existing = mostRecentPerformed[entry.exerciseID] {
                    mostRecentPerformed[entry.exerciseID] = max(existing, record.endedAt)
                } else {
                    mostRecentPerformed[entry.exerciseID] = record.endedAt
                }
            }
        }

        if let neverPerformed = exercises.first(where: { mostRecentPerformed[$0.id] == nil }) {
            return .exercise(neverPerformed)
        }

        let leastRecent = exercises.enumerated().min { lhs, rhs in
            let lhsDate = mostRecentPerformed[lhs.element.id] ?? .distantFuture
            let rhsDate = mostRecentPerformed[rhs.element.id] ?? .distantFuture
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return lhs.offset < rhs.offset
        }?.element
        return leastRecent.map(WorkoutReminderRecommendation.exercise)
    }
}

/// Selects the advertised target, reconciles the bounded local schedule, and resolves reminder taps.
@MainActor
final class WorkoutReminderCoordinator: WorkoutReminderManaging {
    private let preferences: any AppPreferencesStoring
    private let routines: (any RoutineRepository)?
    private let workoutHistory: (any WorkoutHistoryRepository)?
    private let exerciseCatalog: any ExerciseCatalogProviding
    private let router: AppRouter
    private let scheduler: any WorkoutReminderScheduling
    private let now: () -> Date
    private let calendar: Calendar
    /// Each reconciliation waits for the previous one so overlapping triggers cannot interleave remove and add.
    private var latestReconciliation: Task<Void, Never>?

    init(
        preferences: any AppPreferencesStoring,
        routines: (any RoutineRepository)?,
        workoutHistory: (any WorkoutHistoryRepository)?,
        exerciseCatalog: any ExerciseCatalogProviding,
        router: AppRouter,
        scheduler: (any WorkoutReminderScheduling)? = nil,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.preferences = preferences
        self.routines = routines
        self.workoutHistory = workoutHistory
        self.exerciseCatalog = exerciseCatalog
        self.router = router
        self.scheduler = scheduler ?? UserNotificationWorkoutReminderScheduler()
        self.now = now
        self.calendar = calendar
    }

    func reconcile() {
        enqueueReconciliation(requestAuthorizationIfNeeded: false)
    }

    func enable() async {
        await enqueueReconciliation(requestAuthorizationIfNeeded: true).value
    }

    @discardableResult
    private func enqueueReconciliation(requestAuthorizationIfNeeded: Bool) -> Task<Void, Never> {
        let previous = latestReconciliation
        let task = Task {
            await previous?.value
            await reconcileNow(requestAuthorizationIfNeeded: requestAuthorizationIfNeeded)
        }
        latestReconciliation = task
        return task
    }

    func authorizationStatus() async -> WorkoutReminderAuthorizationStatus {
        await scheduler.authorizationStatus()
    }

    func reconcileNow(requestAuthorizationIfNeeded: Bool = false) async {
        let settings = preferences.workoutReminderSettings
        guard settings.enabled else {
            await scheduler.replaceRequests([])
            return
        }

        var authorization = await scheduler.authorizationStatus()
        if authorization == .notDetermined && requestAuthorizationIfNeeded {
            authorization = await scheduler.requestAuthorization()
        }
        guard authorization == .authorized else {
            await scheduler.replaceRequests([])
            return
        }

        let recommendation = currentRecommendation()
        guard let recommendation else {
            await scheduler.replaceRequests([])
            return
        }

        let copy = notificationCopy(for: recommendation)
        let requests = WorkoutReminderScheduleBuilder.requests(
            settings: settings,
            title: "Time for exercise",
            body: copy,
            target: recommendation.target,
            now: now(),
            calendar: calendar
        )
        await scheduler.replaceRequests(requests)
    }

    /// Called by the notification delegate after the router is ready.
    func handleTap(_ target: WorkoutReminderTarget) {
        if case .workout? = router.presentedFullScreenRoute {
            return
        }

        if startAdvertisedTargetIfValid(target) { return }

        if let recommendation = currentRecommendation() {
            start(recommendation)
            return
        }

        switch target {
        case .routine:
            // The Routines list is that tab's root, so select the tab instead of pushing a second copy.
            router.select(.routines)
        case .exercise:
            router.open(.library)
        }
    }

    private func currentRecommendation() -> WorkoutReminderRecommendation? {
        let savedRoutines = (try? routines?.listWithUpdateDates()) ?? []
        let records = (try? workoutHistory?.list()) ?? []
        return WorkoutReminderRecommendationSelector.select(
            routines: savedRoutines,
            records: records,
            override: preferences.upNextOverride,
            exerciseCatalog: exerciseCatalog,
            preferences: preferences
        )
    }

    private func notificationCopy(for recommendation: WorkoutReminderRecommendation) -> String {
        switch recommendation {
        case .routine(let routine):
            let estimate = RoutineEstimator.minutes(
                for: routine,
                exercises: exerciseCatalog.all,
                restPolicy: preferences.restPolicy
            )
            return "How about \(routine.name)? · about \(estimate) min"
        case .exercise(let exercise):
            let target = "\(exercise.sets) × \(exercise.targetLabel)" + (exercise.perSide ? " / side" : "")
            return "How about \(exercise.presentation.shortName)? · \(target)"
        }
    }

    private func startAdvertisedTargetIfValid(_ target: WorkoutReminderTarget) -> Bool {
        switch target {
        case .routine(let id):
            guard let routine = (try? routines?.list())?.first(where: { $0.id == id }),
                  !routine.plan(in: exerciseCatalog.all).items.isEmpty else { return false }
            router.open(.workout(exerciseID: nil, routineID: id))
            return true
        case .exercise(let id):
            guard exerciseCatalog.exercise(id) != nil else { return false }
            router.open(.workout(exerciseID: id, routineID: nil))
            return true
        }
    }

    private func start(_ recommendation: WorkoutReminderRecommendation) {
        switch recommendation {
        case .routine(let routine):
            router.open(.workout(exerciseID: nil, routineID: routine.id))
        case .exercise(let exercise):
            router.open(.workout(exerciseID: exercise.id, routineID: nil))
        }
    }
}
