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
    private let scenarioCatalog: NotificationScenarioCatalog?
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
        scenarioCatalog: NotificationScenarioCatalog? = try? NotificationScenarioCatalog.bundled(),
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.preferences = preferences
        self.routines = routines
        self.workoutHistory = workoutHistory
        self.exerciseCatalog = exerciseCatalog
        self.router = router
        self.scheduler = scheduler ?? UserNotificationWorkoutReminderScheduler()
        self.scenarioCatalog = scenarioCatalog
        self.now = now
        self.calendar = calendar
    }

    func reconcile() {
        enqueueReconciliation {
            await self.reconcileNow(requestAuthorizationIfNeeded: false)
        }
    }

    func enable() async {
        await enqueueReconciliation {
            await self.reconcileNow(requestAuthorizationIfNeeded: true)
        }.value
    }

    func workoutSaved(_ record: WorkoutRecord) {
        enqueueReconciliation {
            await self.reconcileNow()
            await self.acknowledge(record)
        }
    }

    @discardableResult
    private func enqueueReconciliation(
        operation: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        let previous = latestReconciliation
        let task = Task {
            await previous?.value
            await operation()
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

        let currentTime = now()
        let requests: [WorkoutReminderNotificationRequest]
        if settings.style == .character, let scenarioCatalog {
            let records = (try? workoutHistory?.list()) ?? []
            let introDate = preferences.characterNotificationIntroDate
            let isFirstEverNotification = introDate.map { $0 > currentTime } ?? true
            let planned = NotificationPlanner.plan(
                records: records,
                settings: settings,
                now: currentTime,
                calendar: calendar,
                suggestion: notificationSuggestion(for: recommendation),
                isFirstEverNotification: isFirstEverNotification,
                catalog: scenarioCatalog
            )
            requests = planned.map { notification in
                WorkoutReminderNotificationRequest(
                    identifier: notification.identifier,
                    title: notification.content.title,
                    body: notification.content.body,
                    target: recommendation.target,
                    dateComponents: notification.fireDate,
                    repeats: false,
                    imageAssetName: notification.content.imageAssetName,
                    categoryIdentifier: notification.content.categoryIdentifier
                )
            }
            // Only a reminder slot can carry the introduction. If today's earliest remaining slot is a
            // follow-up, leave the date unset so the next day's reminder still introduces the character.
            if isFirstEverNotification,
               let earliest = planned.first,
               earliest.slot == .reminder,
               let date = calendar.date(from: earliest.fireDate) {
                preferences.characterNotificationIntroDate = date
            }
        } else {
            requests = plainRequests(for: recommendation, settings: settings, now: currentTime)
        }
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

    private func plainRequests(
        for recommendation: WorkoutReminderRecommendation,
        settings: WorkoutReminderSettings,
        now: Date
    ) -> [WorkoutReminderNotificationRequest] {
        WorkoutReminderScheduleBuilder.requests(
            settings: settings,
            title: "Time for exercise",
            body: notificationCopy(for: recommendation),
            target: recommendation.target,
            now: now,
            calendar: calendar
        )
    }

    /// Creates the compact suggestion value used inside character notification copy.
    private func notificationSuggestion(for recommendation: WorkoutReminderRecommendation) -> String {
        switch recommendation {
        case .routine(let routine):
            let estimate = RoutineEstimator.minutes(
                for: routine,
                exercises: exerciseCatalog.all,
                restPolicy: preferences.restPolicy
            )
            return "\(routine.name) · about \(estimate) min"
        case .exercise(let exercise):
            let target = "\(exercise.sets) × \(exercise.targetLabel)" + (exercise.perSide ? " / side" : "")
            return "\(exercise.presentation.shortName) · \(target)"
        }
    }

    /// Preserves the established punctuation and phrasing used by plain-mode reminders.
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

    /// Selects and schedules a character acknowledgment after the reminder schedule has been refreshed.
    private func acknowledge(_ record: WorkoutRecord) async {
        let settings = preferences.workoutReminderSettings
        guard settings.enabled,
              settings.style == .character,
              let scenarioCatalog,
              await scheduler.authorizationStatus() == .authorized else { return }

        var records = (try? workoutHistory?.list()) ?? []
        if !records.contains(where: { $0.id == record.id }) {
            records.append(record)
        }
        guard let selection = NotificationScenarioSelector.acknowledgment(
            for: record,
            records: records,
            settings: settings,
            calendar: calendar
        ),
        let scenario = scenarioCatalog.scenario(id: selection.scenarioID) else { return }

        let dayNumber = NotificationCopyPicker.dayNumber(for: record.endedAt, calendar: calendar)
        let variant = NotificationCopyPicker.variant(
            scenarioID: scenario.id,
            dayNumber: dayNumber,
            slotIndex: 0
        )
        guard let content = NotificationContentBuilder.make(
            scenario: scenario,
            variant: variant,
            values: selection.values
        ) else { return }

        await scheduler.scheduleAcknowledgment(WorkoutAcknowledgmentRequest(
            identifier: WorkoutAcknowledgmentRequest.identifierPrefix + record.id.uuidString,
            title: content.title,
            body: content.body,
            imageAssetName: content.imageAssetName,
            categoryIdentifier: content.categoryIdentifier,
            delaySeconds: NotificationPolicy.standard.acknowledgmentDelaySeconds
        ))
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
