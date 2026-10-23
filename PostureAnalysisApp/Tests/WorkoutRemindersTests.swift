import Foundation
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class WorkoutRemindersTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private let catalog = LiveExerciseCatalog()

    func testDisabledReminderReconciliationRemovesPendingRequests() async {
        let preferences = InMemoryPreferences()
        let scheduler = MemoryWorkoutReminderScheduler()
        scheduler.requests = [placeholderRequest()]
        let coordinator = makeCoordinator(preferences: preferences, scheduler: scheduler)

        await coordinator.reconcileNow()

        XCTAssertTrue(scheduler.requests.isEmpty)
    }

    func testDailyUsesSelectedLocalHourAndMinute() {
        let requests = makeSchedule(settings: settings(recurrence: .daily, hour: 18, minute: 25))

        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].repeats)
        XCTAssertEqual(requests[0].dateComponents.hour, 18)
        XCTAssertEqual(requests[0].dateComponents.minute, 25)
        XCTAssertNil(requests[0].dateComponents.weekday)
        XCTAssertNil(requests[0].dateComponents.day)
    }

    func testWeeklySchedulesOnlySelectedWeekdaysAndSupportsMultipleDays() {
        let requests = makeSchedule(settings: settings(recurrence: .weekly, weekdays: [2, 4, 6]))

        XCTAssertEqual(requests.map(\.dateComponents.weekday), [2, 4, 6])
        XCTAssertTrue(requests.allSatisfy(\.repeats))
        XCTAssertEqual(Set(requests.map(\.identifier)).count, 3)
    }

    func testEveryOtherDayUsesTwoCalendarDayStepsFromStartDate() {
        let start = date(2026, 10, 17)
        let requests = makeSchedule(
            settings: settings(recurrence: .everyOtherDay, startDate: start),
            now: date(2026, 10, 17, hour: 10)
        )
        let days = requests.prefix(5).compactMap { request in
            calendar.date(from: request.dateComponents).map { calendar.component(.day, from: $0) }
        }

        XCTAssertEqual(days, [17, 19, 21, 23, 25])
        XCTAssertEqual(requests.count, WorkoutReminderScheduleBuilder.everyOtherDayHorizon)
        XCTAssertTrue(requests.allSatisfy { !$0.repeats })
    }

    func testEveryOtherDayPreservesLocalTimeAcrossDaylightSavingTime() {
        let requests = makeSchedule(
            settings: settings(recurrence: .everyOtherDay, hour: 18, minute: 30, startDate: date(2026, 3, 7)),
            now: date(2026, 3, 7, hour: 12)
        )
        let first = calendar.date(from: requests[0].dateComponents)!
        let second = calendar.date(from: requests[1].dateComponents)!

        XCTAssertEqual(calendar.component(.hour, from: first), 18)
        XCTAssertEqual(calendar.component(.minute, from: first), 30)
        XCTAssertEqual(calendar.component(.hour, from: second), 18)
        XCTAssertEqual(calendar.component(.minute, from: second), 30)
        XCTAssertEqual(second.timeIntervalSince(first), 47 * 60 * 60, accuracy: 1)
        XCTAssertFalse(requests[0].repeats)
        XCTAssertNil(requests[0].dateComponents.timeZone, "Triggers follow the device's local wall clock.")
    }

    func testChangingRecurrenceTimeAndWeekdaysReplacesPreviousLogicalRequests() async {
        let preferences = InMemoryPreferences()
        preferences.workoutReminderSettings = settings(recurrence: .daily, hour: 8)
        let scheduler = MemoryWorkoutReminderScheduler()
        let coordinator = makeCoordinator(preferences: preferences, scheduler: scheduler)

        await coordinator.reconcileNow()
        XCTAssertEqual(scheduler.requests.count, 1)
        XCTAssertEqual(scheduler.requests[0].dateComponents.hour, 8)

        preferences.workoutReminderSettings = settings(recurrence: .weekly, hour: 9, weekdays: [3, 5])
        await coordinator.reconcileNow()
        XCTAssertEqual(scheduler.requests.count, 2)
        XCTAssertEqual(scheduler.requests.map(\.dateComponents.weekday), [3, 5])
        XCTAssertTrue(scheduler.requests.allSatisfy { $0.dateComponents.hour == 9 })

        preferences.workoutReminderSettings = settings(recurrence: .daily, hour: 7, minute: 15)
        await coordinator.reconcileNow()
        XCTAssertEqual(scheduler.requests.count, 1)
        XCTAssertEqual(scheduler.requests[0].dateComponents.hour, 7)
        XCTAssertEqual(scheduler.requests[0].dateComponents.minute, 15)
        XCTAssertEqual(Set(scheduler.requests.map(\.identifier)).count, 1)
    }

    func testNotificationCopyReusesRoutineEstimateAndSavedExerciseTarget() async {
        let preferences = InMemoryPreferences()
        preferences.workoutReminderSettings = settings(enabled: true)
        let savedRoutine = routine("Upper Body", ids: [.shoulderPress])
        let routineScheduler = MemoryWorkoutReminderScheduler()
        let routineCoordinator = makeCoordinator(
            preferences: preferences,
            routines: MemoryReminderRoutineRepository([savedRoutine]),
            scheduler: routineScheduler
        )

        await routineCoordinator.reconcileNow()

        let estimate = RoutineEstimator.minutes(
            for: savedRoutine.set,
            exercises: catalog.all,
            restPolicy: preferences.restPolicy
        )
        XCTAssertEqual(routineScheduler.requests.first?.body, "How about Upper Body? · about \(estimate) min")

        preferences.setExerciseTarget(
            ExerciseTarget(sets: 3, repMinimum: 12, repMaximum: 15),
            for: ExerciseID.shoulderPress.rawValue
        )
        let exerciseScheduler = MemoryWorkoutReminderScheduler()
        let exerciseCoordinator = makeCoordinator(preferences: preferences, scheduler: exerciseScheduler)

        await exerciseCoordinator.reconcileNow()

        XCTAssertEqual(exerciseScheduler.requests.first?.body, "How about Shoulder Press? · 3 × 12–15")
    }

    func testUpNextRoutineIsRecommended() {
        let first = routine("First", ids: [.shoulderPress], createdAt: date(2026, 1, 1))
        let second = routine("Second", ids: [.airSquat], createdAt: date(2026, 1, 2))
        let result = select(routines: [first, second])

        guard case .routine(let selected)? = result else {
            return XCTFail("Expected the current Up Next routine")
        }
        XCTAssertEqual(selected.id, first.set.id)
    }

    func testUpNextOverrideIsRespectedByReminderRecommendation() {
        let first = routine("First", ids: [.shoulderPress], createdAt: date(2026, 1, 1))
        let second = routine("Second", ids: [.airSquat], createdAt: date(2026, 1, 2))
        let result = select(routines: [first, second], override: second.set.id)

        guard case .routine(let selected)? = result else {
            return XCTFail("Expected the overridden routine")
        }
        XCTAssertEqual(selected.id, second.set.id)
    }

    func testNoStartableRoutineFallsBackToAnExercise() {
        let unstartable = routine("Empty", ids: [])
        let result = select(routines: [unstartable])

        guard case .exercise(let exercise)? = result else {
            return XCTFail("Expected an exercise recommendation")
        }
        XCTAssertEqual(exercise.id, catalog.all[0].id)
    }

    func testNeverPerformedExerciseIsPreferredInStableCatalogOrder() {
        let records = [workout(endedAt: date(2026, 10, 1), entries: [entry(.shoulderPress), entry(.hammerCurl)])]
        let result = select(records: records)

        guard case .exercise(let exercise)? = result else {
            return XCTFail("Expected an exercise recommendation")
        }
        XCTAssertEqual(exercise.id, catalog.all[2].id)
    }

    func testLeastRecentlyPerformedExerciseIsSelectedWhenAllHaveHistory() {
        let records = catalog.all.enumerated().map { index, exercise in
            workout(endedAt: date(2026, 10, 1 + index), entries: [entry(exercise.id)])
        }
        let result = select(records: records)

        guard case .exercise(let exercise)? = result else {
            return XCTFail("Expected an exercise recommendation")
        }
        XCTAssertEqual(exercise.id, catalog.all[0].id)
    }

    func testExercisePerformedInsideSavedRoutineContributesToHistory() {
        let performedInRoutine = catalog.all[3]
        let records = catalog.all.enumerated().map { index, exercise in
            let performed = exercise.id == performedInRoutine.id ? performedInRoutine : exercise
            return workout(
                endedAt: date(2026, 10, exercise.id == performedInRoutine.id ? 1 : 2 + index),
                planID: UUID(),
                planName: "Old routine",
                entries: [entry(performed.id)]
            )
        }
        let result = select(records: records)

        guard case .exercise(let exercise)? = result else {
            return XCTFail("Expected the least recently performed exercise")
        }
        XCTAssertEqual(exercise.id, performedInRoutine.id)
    }

    func testSkippedExerciseDoesNotCountAsPerformed() {
        let completedEntries = catalog.all.dropFirst().map { entry($0.id) }
        let skipped = WorkoutRecordEntry(
            exerciseID: catalog.all[0].id,
            name: catalog.all[0].displayName,
            outcome: .skipped,
            sets: []
        )
        let records = [workout(endedAt: date(2026, 10, 10), entries: completedEntries + [skipped])]
        let result = select(records: records)

        guard case .exercise(let exercise)? = result else {
            return XCTFail("Expected the skipped exercise to remain unperformed")
        }
        XCTAssertEqual(exercise.id, catalog.all[0].id)
    }

    func testPayloadIdentifiesRoutineOrExerciseAndCarriesItsID() {
        let routineID = UUID()
        let routine = WorkoutReminderTarget.routine(routineID)
        let exercise = WorkoutReminderTarget.exercise(.shoulderPress)

        XCTAssertEqual(WorkoutReminderTarget(userInfo: routine.payload), routine)
        XCTAssertEqual(WorkoutReminderTarget(userInfo: exercise.payload), exercise)
        XCTAssertEqual(routine.payload["workoutReminder.targetType"], "routine")
        XCTAssertEqual(routine.payload["workoutReminder.targetID"], routineID.uuidString)
        XCTAssertEqual(exercise.payload["workoutReminder.targetType"], "exercise")
        XCTAssertEqual(exercise.payload["workoutReminder.targetID"], "shoulder_press")
    }

    func testValidRoutineNotificationOpensMatchingRoutineWorkoutRoute() {
        let savedRoutine = routine("Advertised", ids: [.shoulderPress])
        let router = AppRouter()
        let coordinator = makeCoordinator(routines: MemoryReminderRoutineRepository([savedRoutine]), router: router)

        coordinator.handleTap(.routine(savedRoutine.set.id))

        XCTAssertEqual(router.presentedFullScreenRoute, .workout(exerciseID: nil, routineID: savedRoutine.set.id))
    }

    func testValidExerciseNotificationOpensMatchingExerciseWorkoutRoute() {
        let router = AppRouter()
        let coordinator = makeCoordinator(router: router)

        coordinator.handleTap(.exercise(.airSquat))

        XCTAssertEqual(router.presentedFullScreenRoute, .workout(exerciseID: .airSquat, routineID: nil))
    }

    func testStaleRoutineFallsBackToCurrentRoutineRecommendation() {
        let current = routine("Current", ids: [.airSquat])
        let router = AppRouter()
        let coordinator = makeCoordinator(routines: MemoryReminderRoutineRepository([current]), router: router)

        coordinator.handleTap(.routine(UUID()))

        XCTAssertEqual(router.presentedFullScreenRoute, .workout(exerciseID: nil, routineID: current.set.id))
    }

    func testStaleRoutineFallsBackToHistoryAwareExerciseRecommendation() {
        let router = AppRouter()
        let coordinator = makeCoordinator(router: router)

        coordinator.handleTap(.routine(UUID()))

        XCTAssertEqual(router.presentedFullScreenRoute, .workout(exerciseID: catalog.all[0].id, routineID: nil))
    }

    func testStaleExerciseFallsBackToCurrentRoutineRecommendation() {
        let current = routine("Current", ids: [.airSquat])
        let router = AppRouter()
        let coordinator = makeCoordinator(routines: MemoryReminderRoutineRepository([current]), router: router)

        coordinator.handleTap(.exercise(ExerciseID(rawValue: "removed_exercise")))

        XCTAssertEqual(router.presentedFullScreenRoute, .workout(exerciseID: nil, routineID: current.set.id))
    }

    func testNoValidRecommendationSchedulesNothingAndRoutesStaleRoutineToRoutines() async {
        let preferences = InMemoryPreferences()
        preferences.workoutReminderSettings = settings(enabled: true)
        let scheduler = MemoryWorkoutReminderScheduler()
        let router = AppRouter()
        let coordinator = WorkoutReminderCoordinator(
            preferences: preferences,
            routines: MemoryReminderRoutineRepository([routine("Empty", ids: [])]),
            workoutHistory: MemoryReminderHistoryRepository(),
            exerciseCatalog: MemoryReminderExerciseCatalog(exercises: []),
            router: router,
            scheduler: scheduler,
            now: { self.date(2026, 10, 17) },
            calendar: calendar
        )

        await coordinator.reconcileNow()
        coordinator.handleTap(.routine(UUID()))

        XCTAssertTrue(scheduler.requests.isEmpty)
        XCTAssertEqual(router.selectedTab, .routines)
        XCTAssertEqual(router.path(for: .routines), [])
    }

    func testNotificationTapDoesNotReplaceAnActiveWorkout() {
        let router = AppRouter()
        let activeRoute = AppRoute.workout(exerciseID: .hammerCurl, routineID: nil)
        router.open(activeRoute)
        let coordinator = makeCoordinator(router: router)

        coordinator.handleTap(.exercise(.airSquat))

        XCTAssertEqual(router.presentedFullScreenRoute, activeRoute)
    }

    func testEnablingRequestsAuthorizationOnlyWhenStatusIsNotDetermined() async {
        let preferences = InMemoryPreferences()
        preferences.workoutReminderSettings = settings(enabled: true)
        let scheduler = MemoryWorkoutReminderScheduler(status: .notDetermined)
        let coordinator = makeCoordinator(preferences: preferences, scheduler: scheduler)

        await coordinator.enable()

        XCTAssertEqual(scheduler.authorizationRequestCount, 1)
        XCTAssertFalse(scheduler.requests.isEmpty)

        scheduler.status = .denied
        await coordinator.enable()
        XCTAssertEqual(scheduler.authorizationRequestCount, 1)
        XCTAssertTrue(scheduler.requests.isEmpty)
    }

    private func settings(
        enabled: Bool = true,
        recurrence: WorkoutReminderRecurrence = .daily,
        hour: Int = 18,
        minute: Int = 0,
        startDate: Date = Calendar(identifier: .gregorian).startOfDay(for: Date(timeIntervalSince1970: 0)),
        weekdays: Set<Int> = [2, 4, 6]
    ) -> WorkoutReminderSettings {
        WorkoutReminderSettings(
            enabled: enabled,
            style: .plain,
            recurrence: recurrence,
            hour: hour,
            minute: minute,
            everyOtherDayStartDate: startDate,
            weekdays: weekdays
        )
    }

    private func makeSchedule(
        settings: WorkoutReminderSettings,
        now: Date = Date(timeIntervalSince1970: 0)
    ) -> [WorkoutReminderNotificationRequest] {
        WorkoutReminderScheduleBuilder.requests(
            settings: settings,
            title: "Time for exercise",
            body: "How about Shoulder Press?",
            target: .exercise(.shoulderPress),
            now: now,
            calendar: calendar
        )
    }

    private func select(
        routines: [SavedExerciseSetRecord] = [],
        records: [WorkoutRecord] = [],
        override: UUID? = nil
    ) -> WorkoutReminderRecommendation? {
        WorkoutReminderRecommendationSelector.select(
            routines: routines,
            records: records,
            override: override,
            exerciseCatalog: catalog,
            preferences: InMemoryPreferences()
        )
    }

    private func makeCoordinator(
        preferences: InMemoryPreferences = InMemoryPreferences(),
        routines: MemoryReminderRoutineRepository? = nil,
        records: [WorkoutRecord] = [],
        exerciseCatalog: any ExerciseCatalogProviding = LiveExerciseCatalog(),
        scheduler: MemoryWorkoutReminderScheduler? = nil,
        router: AppRouter? = nil
    ) -> WorkoutReminderCoordinator {
        WorkoutReminderCoordinator(
            preferences: preferences,
            routines: routines ?? MemoryReminderRoutineRepository([]),
            workoutHistory: MemoryReminderHistoryRepository(records: records),
            exerciseCatalog: exerciseCatalog,
            router: router ?? AppRouter(),
            scheduler: scheduler ?? MemoryWorkoutReminderScheduler(),
            now: { self.date(2026, 10, 17, hour: 10) },
            calendar: calendar
        )
    }

    private func routine(_ name: String, ids: [ExerciseID], createdAt: Date? = nil) -> SavedExerciseSetRecord {
        let set = SavedExerciseSet(name: name, items: ids.map { id in
            let exercise = catalog.exercise(id)!
            return SavedExerciseSetItem(
                exerciseID: id,
                setCount: 2,
                targetRepMinimum: exercise.targetReps.lowerBound,
                targetRepMaximum: exercise.targetReps.upperBound
            )
        })
        let timestamp = createdAt ?? date(2026, 1, 1)
        return SavedExerciseSetRecord(set: set, createdAt: timestamp, updatedAt: timestamp)
    }

    private func entry(
        _ id: ExerciseID,
        outcome: WorkoutRecordEntry.Outcome? = .completed
    ) -> WorkoutRecordEntry {
        WorkoutRecordEntry(
            exerciseID: id,
            name: catalog.exercise(id)?.displayName ?? id.rawValue,
            outcome: outcome,
            sets: outcome == .skipped ? [] : [RecordedSet(reps: 1)]
        )
    }

    private func workout(
        endedAt: Date,
        planID: UUID? = nil,
        planName: String? = nil,
        entries: [WorkoutRecordEntry]
    ) -> WorkoutRecord {
        WorkoutRecord(
            startedAt: endedAt.addingTimeInterval(-600),
            endedAt: endedAt,
            planID: planID,
            planName: planName,
            entries: entries
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func placeholderRequest() -> WorkoutReminderNotificationRequest {
        WorkoutReminderNotificationRequest(
            identifier: "old",
            title: "Old",
            body: "Old",
            target: .exercise(.shoulderPress),
            dateComponents: DateComponents(hour: 8),
            repeats: true
        )
    }
}

@MainActor
private final class MemoryReminderRoutineRepository: RoutineRepository {
    let entries: [SavedExerciseSetRecord]

    init(_ entries: [SavedExerciseSetRecord]) {
        self.entries = entries
    }

    func list() throws -> [SavedExerciseSet] { entries.map(\.set) }
    func listWithUpdateDates() throws -> [SavedExerciseSetRecord] { entries }
    func save(_ set: SavedExerciseSet) throws {}
    func duplicate(_ set: SavedExerciseSet) throws -> SavedExerciseSet { set.duplicated() }
    func delete(id: UUID) throws {}
}

@MainActor
private final class MemoryReminderHistoryRepository: WorkoutHistoryRepository {
    let records: [WorkoutRecord]

    init(records: [WorkoutRecord] = []) {
        self.records = records
    }

    func list() throws -> [WorkoutRecord] { records }
    func save(_ record: WorkoutRecord) throws {}
    func updateWeights(for record: WorkoutRecord) throws {}
    func delete(id: UUID) throws {}
}

private struct MemoryReminderExerciseCatalog: ExerciseCatalogProviding {
    let exercises: [ExerciseDefinition]
    var all: [ExerciseDefinition] { exercises }
    func exercise(_ id: ExerciseID) -> ExerciseDefinition? { exercises.first { $0.id == id } }
}
