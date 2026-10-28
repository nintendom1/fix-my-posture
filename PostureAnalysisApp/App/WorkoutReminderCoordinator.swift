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
    private let eventLog: any NotificationEventRecording
    private let now: () -> Date
    private let calendar: Calendar
    private let assessments: (any AssessmentRepository)?
    private let personaCatalog: PersonaContentCatalog?
    private let personaTraces: (any PersonaTraceStoring)?
    private let quietHours: any QuietHoursProviding
    private let personaPolicy: PersonaPolicy
    private let isAppActive: () -> Bool
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
        eventLog: any NotificationEventRecording = NoNotificationEventLog(),
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        assessments: (any AssessmentRepository)? = nil,
        personaCatalog: PersonaContentCatalog? = nil,
        personaTraces: (any PersonaTraceStoring)? = nil,
        quietHours: any QuietHoursProviding = FixedQuietHours(),
        personaPolicy: PersonaPolicy = .standard,
        isAppActive: @escaping () -> Bool = { true }
    ) {
        self.preferences = preferences
        self.routines = routines
        self.workoutHistory = workoutHistory
        self.exerciseCatalog = exerciseCatalog
        self.router = router
        self.eventLog = eventLog
        self.scheduler = scheduler ?? UserNotificationWorkoutReminderScheduler(eventLog: eventLog)
        self.scenarioCatalog = scenarioCatalog
        self.now = now
        self.calendar = calendar
        self.assessments = assessments
        self.personaCatalog = personaCatalog
        self.personaTraces = personaTraces
        self.quietHours = quietHours
        self.personaPolicy = personaPolicy
        self.isAppActive = isAppActive
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
            self.eventLog.record(
                "workoutSaved: workout ended \(record.endedAt.eventLogDescription(in: self.calendar.timeZone))"
            )
            // The acknowledgment step evaluates the persona once, with the saved workout as its trigger.
            await self.reconcileNow(evaluatesPersona: false)
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

    func reconcileNow(requestAuthorizationIfNeeded: Bool = false, evaluatesPersona: Bool = true) async {
        let settings = preferences.workoutReminderSettings
        guard settings.enabled else {
            eventLog.record("reconcile: reminders are off, cleared pending reminders")
            await scheduler.replaceRequests([])
            await clearPersonaRequests()
            return
        }

        var authorization = await scheduler.authorizationStatus()
        if authorization == .notDetermined && requestAuthorizationIfNeeded {
            authorization = await scheduler.requestAuthorization()
        }
        guard authorization == .authorized else {
            eventLog.record("reconcile: notifications are not authorized (\(authorization)), cleared pending reminders")
            await scheduler.replaceRequests([])
            await clearPersonaRequests()
            return
        }

        let recommendation = currentRecommendation()
        guard let recommendation else {
            eventLog.record("reconcile: no workout to recommend, cleared pending reminders")
            await scheduler.replaceRequests([])
            if evaluatesPersona { await reconcilePersona() }
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
        let firstFire = requests.first.flatMap { calendar.date(from: $0.dateComponents) }
        eventLog.record(
            "reconcile: \(settings.style.rawValue) style, scheduling \(requests.count) reminders, "
                + "first at \(firstFire?.eventLogDescription(in: calendar.timeZone) ?? "none")"
        )
        await scheduler.replaceRequests(requests)
        if evaluatesPersona { await reconcilePersona() }
    }

    /// Called by the notification delegate after the router is ready.
    func handleTap(_ target: WorkoutReminderTarget) {
        // A tap never replaces a workout in progress, including Today's Session and a calibration.
        switch router.presentedFullScreenRoute {
        case .workout?, .todaySession?, .calibration?: return
        default: break
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

    /// Notes why no acknowledgment was scheduled, so a missing reply can be explained from the log.
    private func skipAcknowledgment(_ reason: String) {
        eventLog.record("ack: skipped, \(reason)")
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
            let target = "\(exercise.sets) × \(exercise.targetLabel)\(exercise.perSideTargetSuffix)"
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
            let target = "\(exercise.sets) × \(exercise.targetLabel)\(exercise.perSideTargetSuffix)"
            return "How about \(exercise.presentation.shortName)? · \(target)"
        }
    }

    /// Selects and schedules a character acknowledgment after the reminder schedule has been refreshed, and evaluates
    /// Extra Personable with the saved workout as its trigger: persona content rides on the acknowledgment when one fires.
    private func acknowledge(_ record: WorkoutRecord) async {
        let settings = preferences.workoutReminderSettings
        guard settings.enabled else { return skipAcknowledgment("reminders are off") }
        guard settings.style == .character else { return skipAcknowledgment("style is Plain") }
        let authorization = await scheduler.authorizationStatus()
        guard authorization == .authorized else {
            return skipAcknowledgment("notifications are not authorized (\(authorization))")
        }

        var records = (try? workoutHistory?.list()) ?? []
        if !records.contains(where: { $0.id == record.id }) {
            records.append(record)
        }
        // The persona evaluates every save, even when the scenario data (and so the acknowledgment) is unavailable.
        let selected: (content: CharacterNotificationContent, variant: Int)?
        if let scenarioCatalog {
            selected = acknowledgmentContent(for: record, records: records, settings: settings, catalog: scenarioCatalog)
        } else {
            skipAcknowledgment("scenario data is missing")
            selected = nil
        }
        let personaPlan = await applyPersonaPlan(trigger: .workoutSaved(record), records: records, acknowledgmentWillFire: selected != nil)
        guard let selected else { return }
        var content = selected.content

        switch personaPlan?.immediate {
        case .fold(.replace(let persona))?:
            content = CharacterNotificationContent(
                scenarioID: content.scenarioID, kind: content.kind, title: persona.title, body: persona.body,
                imageAssetName: persona.imageAssetName, artLabel: persona.artLabel
            )
            eventLog.record("persona: replaced the acknowledgment with \(persona.scenarioID)")
        case .fold(.append(let line))?:
            content = CharacterNotificationContent(
                scenarioID: content.scenarioID, kind: content.kind, title: content.title, body: content.body + "\n" + line,
                imageAssetName: content.imageAssetName, artLabel: content.artLabel
            )
            eventLog.record("persona: added a line to the acknowledgment")
        default:
            break
        }

        eventLog.record(
            "ack: scheduling \(content.scenarioID) variant \(selected.variant) in \(NotificationPolicy.standard.acknowledgmentDelaySeconds)s"
        )
        await scheduler.scheduleAcknowledgment(WorkoutAcknowledgmentRequest(
            identifier: WorkoutAcknowledgmentRequest.identifierPrefix + record.id.uuidString,
            title: content.title,
            body: content.body,
            imageAssetName: content.imageAssetName,
            categoryIdentifier: content.categoryIdentifier,
            delaySeconds: NotificationPolicy.standard.acknowledgmentDelaySeconds
        ))
    }

    /// The day's acknowledgment content, or nil (with a logged reason) when none should fire.
    private func acknowledgmentContent(
        for record: WorkoutRecord,
        records: [WorkoutRecord],
        settings: WorkoutReminderSettings,
        catalog: NotificationScenarioCatalog
    ) -> (content: CharacterNotificationContent, variant: Int)? {
        guard let selection = NotificationScenarioSelector.acknowledgment(
            for: record,
            records: records,
            settings: settings,
            calendar: calendar
        ) else {
            skipAcknowledgment("not the first workout of the day")
            return nil
        }
        guard let scenario = catalog.scenario(id: selection.scenarioID) else {
            skipAcknowledgment("unknown scenario \(selection.scenarioID)")
            return nil
        }
        let dayNumber = NotificationCopyPicker.dayNumber(for: record.endedAt, calendar: calendar)
        let variant = NotificationCopyPicker.variant(scenarioID: scenario.id, dayNumber: dayNumber, slotIndex: 0)
        guard let content = NotificationContentBuilder.make(scenario: scenario, variant: variant, values: selection.values) else {
            skipAcknowledgment("no content for \(scenario.id)")
            return nil
        }
        return (content, variant)
    }

    // MARK: Extra Personable

    /// Projected persona evaluation on reconciliation: replaces pending projected persona requests.
    private func reconcilePersona() async {
        let records = (try? workoutHistory?.list()) ?? []
        _ = await applyPersonaPlan(trigger: .reconcile, records: records, acknowledgmentWillFire: false)
    }

    /// Removes every pending persona request when the persona cannot speak, and forgets their pending traces so they
    /// never read later as delivered-but-ignored messages (which would trigger cooling) or block their keys.
    private func clearPersonaRequests() async {
        guard let personaTraces else { return }
        dropPendingTraces(in: personaTraces)
        await scheduler.removeAllPersonaRequests()
    }

    private func dropPendingTraces(in store: any PersonaTraceStoring) {
        var state = store.load()
        let currentTime = now()
        guard state.sent.contains(where: { $0.isPending(asOf: currentTime) }) else { return }
        state.sent.removeAll { $0.isPending(asOf: currentTime) }
        store.save(state)
    }

    /// Builds the context, runs the planner, records traces, and schedules standalone requests. Returns the plan so the
    /// acknowledgment can apply a fold. Returns nil when Extra Personable is unavailable (no content or trace store).
    @discardableResult
    private func applyPersonaPlan(
        trigger: PersonaTrigger,
        records: [WorkoutRecord],
        acknowledgmentWillFire: Bool
    ) async -> PersonaPlan? {
        guard let personaCatalog, let personaTraces else { return nil }
        let currentTime = now()
        let state = personaTraces.load()
        let context = personaContext(trigger: trigger, records: records, state: state, acknowledgmentWillFire: acknowledgmentWillFire, now: currentTime)
        guard context.isActive else {
            if state.sent.contains(where: { $0.isPending(asOf: currentTime) }) {
                eventLog.record("persona: off (Extra Personable \(context.extraPersonableEnabled ? "on" : "off")), cleared persona requests")
            }
            dropPendingTraces(in: personaTraces)
            await scheduler.removeAllPersonaRequests()
            return nil
        }
        let plan = PersonaPlanner.plan(context: context, quietHours: quietHours, catalog: personaCatalog, policy: personaPolicy)
        var updated = state
        updated.replacePending(with: plan.traces, now: currentTime, policy: personaPolicy)
        // Traces are saved as sent before iOS accepts the request; a refusal is logged by the adapter and, like a refused
        // reminder, is not retried until the next reconciliation.
        personaTraces.save(updated)

        if case .standalone(let request)? = plan.immediate {
            await scheduler.addPersonaRequest(request)
        }
        await scheduler.replacePersonaRequests(plan.scheduled)
        eventLog.record(
            "persona: \(trigger == .reconcile ? "reconcile" : "workout saved"), immediate \(Self.describe(plan.immediate)), "
                + "scheduled \(plan.scheduled.count), suppressed \(plan.traces.filter { $0.suppressionReason != nil }.count)"
        )
        return plan
    }

    private static func describe(_ immediate: PersonaImmediate?) -> String {
        switch immediate {
        case nil: "none"
        case .fold(.replace)?: "fold-replace"
        case .fold(.append)?: "fold-append"
        case .standalone(let request)?: "standalone \(request.interruption.rawValue)"
        case .inAppOnly?: "in-app only"
        }
    }

    private func personaContext(
        trigger: PersonaTrigger,
        records: [WorkoutRecord],
        state: PersonaTraceState,
        acknowledgmentWillFire: Bool,
        now currentTime: Date
    ) -> PersonaContext {
        PersonaContextBuilder.build(
            history: personaHistory(records: records),
            settings: preferences.workoutReminderSettings,
            extraPersonableEnabled: preferences.extraPersonableEnabled,
            personaResetDate: preferences.personaResetDate,
            traceState: state,
            trigger: trigger,
            acknowledgmentWillFire: acknowledgmentWillFire,
            appIsActive: isAppActive(),
            now: currentTime,
            calendar: calendar,
            policy: personaPolicy
        )
    }

    private func personaHistory(records: [WorkoutRecord]) -> PersonaHistory {
        let savedRoutines = (try? routines?.list()) ?? []
        let exercises = exerciseCatalog.all
        return PersonaHistory(
            records: records,
            assessments: (try? assessments?.list()) ?? [],
            routineNames: Dictionary(savedRoutines.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }),
            routineMinutes: Dictionary(
                savedRoutines.map { ($0.id, RoutineEstimator.minutes(for: $0, exercises: exercises, restPolicy: preferences.restPolicy)) },
                uniquingKeysWith: { first, _ in first }
            ),
            exerciseNames: Dictionary(exercises.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        )
    }

    /// Records a persona notification tap or dismissal. Frequency signal only.
    func recordPersonaEngagement(_ event: PersonaEngagementEvent) {
        guard let personaTraces else { return }
        var state = personaTraces.load()
        state.record(event, policy: personaPolicy)
        personaTraces.save(state)
        eventLog.record("persona: \(event.kind.rawValue) \(event.observationKey)")
    }

    /// Reset Persona: familiarity starts over from now; history and the Extra Personable setting stay.
    func resetPersona() async {
        await enqueueReconciliation {
            self.preferences.personaResetDate = self.now()
            if let personaTraces = self.personaTraces {
                personaTraces.save(.empty)
            }
            await self.scheduler.removeAllPersonaRequests()
            self.eventLog.record("persona: reset")
            await self.reconcileNow()
        }.value
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

extension WorkoutReminderCoordinator: PersonaDebugProviding {
    func personaStatus() -> PersonaStatus {
        guard let personaTraces else { return .inactive }
        let currentTime = now()
        let state = personaTraces.load()
        let records = (try? workoutHistory?.list()) ?? []
        let context = personaContext(trigger: .reconcile, records: records, state: state, acknowledgmentWillFire: false, now: currentTime)
        let today = calendar.startOfDay(for: currentTime)
        let firedToday = state.fired(asOf: currentTime).filter {
            $0.delivery.isStandalone && $0.fireDate.map { calendar.isDate($0, inSameDayAs: today) } == true
        }
        return PersonaStatus(
            extraPersonableEnabled: preferences.extraPersonableEnabled,
            isActive: context.isActive && personaCatalog != nil,
            familiarity: context.familiarity,
            trajectory: context.trajectory,
            cooling: PersonaCooling.level(engagement: state.engagement, sent: state.fired(asOf: currentTime), now: currentTime, policy: personaPolicy),
            standaloneCountToday: firedToday.count,
            dailyCap: personaPolicy.dailyStandaloneCap,
            pendingCount: state.sent.filter { $0.isPending(asOf: currentTime) }.count,
            quietHoursSummary: quietHours.summary,
            isQuietNow: quietHours.quietInterval(containing: currentTime, calendar: calendar) != nil,
            personaResetDate: preferences.personaResetDate
        )
    }

    func personaTraceState() -> PersonaTraceState {
        personaTraces?.load() ?? .empty
    }

    func runPersonaDetectorsNow() async {
        await enqueueReconciliation {
            await self.reconcileNow()
        }.value
    }
}
