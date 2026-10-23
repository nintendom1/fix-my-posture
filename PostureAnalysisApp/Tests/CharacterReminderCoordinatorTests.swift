import Foundation
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class CharacterReminderCoordinatorTests: XCTestCase {
    private let exerciseCatalog = LiveExerciseCatalog()

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }

    func testCharacterPlansDatedRequestsWithSuggestionArtAndUniqueIdentifiers() async throws {
        let scenarioCatalog = try NotificationScenarioCatalog.bundled()
        let preferences = InMemoryPreferences()
        preferences.workoutReminderSettings = settings(style: .character)
        let scheduler = MemoryWorkoutReminderScheduler()
        let coordinator = makeCoordinator(
            preferences: preferences,
            scheduler: scheduler,
            scenarioCatalog: scenarioCatalog,
            now: { self.date(2026, 10, 17, hour: 10) }
        )

        await coordinator.reconcileNow()

        XCTAssertFalse(scheduler.requests.isEmpty)
        XCTAssertTrue(scheduler.requests.allSatisfy { !$0.repeats })
        XCTAssertTrue(scheduler.requests.allSatisfy { $0.target == .exercise(.shoulderPress) })
        XCTAssertTrue(scheduler.requests.allSatisfy { $0.imageAssetName != nil })
        XCTAssertTrue(scheduler.requests.allSatisfy {
            $0.categoryIdentifier == NotificationCategory.nudge
        })
        XCTAssertEqual(Set(scheduler.requests.map(\.identifier)).count, scheduler.requests.count)
        XCTAssertLessThanOrEqual(scheduler.requests.count, NotificationPolicy.standard.maximumRequests)
        let fireDates = scheduler.requests.compactMap { calendar.date(from: $0.dateComponents) }
        XCTAssertEqual(fireDates, fireDates.sorted())
        let firstRequest = try XCTUnwrap(scheduler.requests.first)
        XCTAssertTrue(firstRequest.title.contains(exerciseSuggestion()))
    }

    func testCharacterRoutineSuggestionUsesTheExistingDurationEstimate() async throws {
        let scenarioCatalog = try NotificationScenarioCatalog.bundled()
        let preferences = InMemoryPreferences()
        preferences.workoutReminderSettings = settings(style: .character)
        let savedRoutine = routine("Upper Body", exercises: [.shoulderPress])
        let scheduler = MemoryWorkoutReminderScheduler()
        let coordinator = makeCoordinator(
            preferences: preferences,
            routines: ReminderRoutineRepository([savedRoutine]),
            scheduler: scheduler,
            scenarioCatalog: scenarioCatalog,
            now: { self.date(2026, 10, 17, hour: 10) }
        )

        await coordinator.reconcileNow()

        let minutes = RoutineEstimator.minutes(
            for: savedRoutine.set,
            exercises: exerciseCatalog.all,
            restPolicy: preferences.restPolicy
        )
        let firstRequest = try XCTUnwrap(scheduler.requests.first)
        XCTAssertTrue(firstRequest.title.contains("Upper Body · about \(minutes) min"))
        XCTAssertTrue(scheduler.requests.allSatisfy { $0.target == .routine(savedRoutine.set.id) })
    }

    func testCharacterExerciseSuggestionUsesSavedPerSideTarget() async throws {
        let scenarioCatalog = try NotificationScenarioCatalog.bundled()
        // The one-arm dumbbell row is the only per-side exercise, so it is the one that adds " / side".
        let exercise = try XCTUnwrap(exerciseCatalog.exercise(.dumbbellRow))
        let preferences = InMemoryPreferences()
        preferences.workoutReminderSettings = settings(style: .character)
        preferences.setExerciseTarget(
            ExerciseTarget(sets: 3, repMinimum: 10, repMaximum: 12),
            for: exercise.id.rawValue
        )
        let scheduler = MemoryWorkoutReminderScheduler()
        let coordinator = makeCoordinator(
            preferences: preferences,
            exerciseCatalog: ReminderExerciseCatalog(exercises: [exercise]),
            scheduler: scheduler,
            scenarioCatalog: scenarioCatalog,
            now: { self.date(2026, 10, 17, hour: 10) }
        )

        await coordinator.reconcileNow()

        let firstRequest = try XCTUnwrap(scheduler.requests.first)
        XCTAssertTrue(firstRequest.title.contains("\(exercise.presentation.shortName) · 3 × 10–12 / side"))
    }

    func testPlainModeMatchesLegacyScheduleBuilderExactly() async throws {
        let preferences = InMemoryPreferences()
        let plainSettings = settings(style: .plain, recurrence: .weekly, weekdays: [2, 4, 6])
        preferences.workoutReminderSettings = plainSettings
        let scheduler = MemoryWorkoutReminderScheduler()
        let now = date(2026, 10, 17, hour: 10)
        let coordinator = makeCoordinator(
            preferences: preferences,
            scheduler: scheduler,
            scenarioCatalog: try NotificationScenarioCatalog.bundled(),
            now: { now }
        )

        await coordinator.reconcileNow()

        let expected = WorkoutReminderScheduleBuilder.requests(
            settings: plainSettings,
            title: "Time for exercise",
            body: legacyExerciseCopy(),
            target: .exercise(.shoulderPress),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(scheduler.requests, expected)
    }

    func testCharacterModeWithoutCatalogFallsBackToPlainRequests() async {
        let preferences = InMemoryPreferences()
        let characterSettings = settings(style: .character)
        preferences.workoutReminderSettings = characterSettings
        let scheduler = MemoryWorkoutReminderScheduler()
        let now = date(2026, 10, 17, hour: 10)
        let coordinator = makeCoordinator(
            preferences: preferences,
            scheduler: scheduler,
            scenarioCatalog: nil,
            now: { now }
        )

        await coordinator.reconcileNow()

        let expected = WorkoutReminderScheduleBuilder.requests(
            settings: characterSettings,
            title: "Time for exercise",
            body: legacyExerciseCopy(),
            target: .exercise(.shoulderPress),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(scheduler.requests, expected)
    }

    func testFirstEverReminderStaysOnEarliestFireUntilItPasses() async throws {
        let scenarioCatalog = try NotificationScenarioCatalog.bundled()
        let preferences = InMemoryPreferences()
        preferences.workoutReminderSettings = settings(style: .character)
        let scheduler = MemoryWorkoutReminderScheduler()
        var now = date(2026, 10, 17, hour: 10)
        let coordinator = makeCoordinator(
            preferences: preferences,
            scheduler: scheduler,
            scenarioCatalog: scenarioCatalog,
            now: { now }
        )

        await coordinator.reconcileNow()
        let firstPlan = scheduler.requests
        let firstFireDate = try XCTUnwrap(firstPlan.first.flatMap { calendar.date(from: $0.dateComponents) })
        let firstEverCopyBody = try firstEverBody(for: firstFireDate, catalog: scenarioCatalog)
        XCTAssertEqual(firstPlan.first?.body, firstEverCopyBody)
        XCTAssertEqual(preferences.characterNotificationIntroDate, firstFireDate)

        now = date(2026, 10, 17, hour: 11)
        await coordinator.reconcileNow()
        let beforeFire = try XCTUnwrap(scheduler.requests.first)
        XCTAssertEqual(calendar.date(from: beforeFire.dateComponents), firstFireDate)
        XCTAssertEqual(beforeFire.body, firstEverCopyBody)
        XCTAssertEqual(preferences.characterNotificationIntroDate, firstFireDate)

        // At the exact fire time the strict comparison must stop classifying later reminders as first-ever.
        now = firstFireDate
        await coordinator.reconcileNow()
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: firstFireDate))
        let nextDayFirstEverBody = try firstEverBody(for: nextDay, catalog: scenarioCatalog)
        XCTAssertFalse(scheduler.requests.contains { $0.body == nextDayFirstEverBody })

        now = firstFireDate.addingTimeInterval(1)
        await coordinator.reconcileNow()
        XCTAssertFalse(scheduler.requests.contains { $0.body == nextDayFirstEverBody })
    }

    func testIntroductionWaitsForAReminderWhenTheEarliestPlannedSlotIsAFollowUp() async throws {
        let scenarioCatalog = try NotificationScenarioCatalog.bundled()
        let preferences = InMemoryPreferences()
        preferences.workoutReminderSettings = settings(style: .character)
        let scheduler = MemoryWorkoutReminderScheduler()
        // A recent workout means follow-ups exist. At 19:00 the 18:00 reminder has passed,
        // so the earliest slot left today is the follow-up.
        let history = ReminderHistoryRepository(records: [workout(endedAt: date(2026, 10, 16, hour: 12))])
        var now = date(2026, 10, 17, hour: 19)
        let coordinator = makeCoordinator(
            preferences: preferences,
            workoutHistory: history,
            scheduler: scheduler,
            scenarioCatalog: scenarioCatalog,
            now: { now }
        )

        await coordinator.reconcileNow()

        XCTAssertTrue(try XCTUnwrap(scheduler.requests.first).identifier.hasSuffix("2026-10-17.1"))
        XCTAssertNil(preferences.characterNotificationIntroDate)

        // The next day's first slot is a reminder, so it carries the introduction and records its time.
        now = date(2026, 10, 18, hour: 8)
        await coordinator.reconcileNow()

        let reminderDate = date(2026, 10, 18, hour: 18)
        XCTAssertEqual(try XCTUnwrap(scheduler.requests.first).body,
                       try firstEverBody(for: reminderDate, catalog: scenarioCatalog))
        XCTAssertEqual(preferences.characterNotificationIntroDate, reminderDate)
    }

    func testDisabledDeniedAndMissingRecommendationCharacterModesScheduleNothing() async throws {
        let scenarioCatalog = try NotificationScenarioCatalog.bundled()

        let disabledPreferences = InMemoryPreferences()
        disabledPreferences.workoutReminderSettings = settings(enabled: false, style: .character)
        let disabledScheduler = MemoryWorkoutReminderScheduler()
        let disabledCoordinator = makeCoordinator(
            preferences: disabledPreferences,
            scheduler: disabledScheduler,
            scenarioCatalog: scenarioCatalog
        )
        await disabledCoordinator.reconcileNow()
        XCTAssertTrue(disabledScheduler.requests.isEmpty)

        let deniedPreferences = InMemoryPreferences()
        deniedPreferences.workoutReminderSettings = settings(style: .character)
        let deniedScheduler = MemoryWorkoutReminderScheduler(status: .denied)
        let deniedCoordinator = makeCoordinator(
            preferences: deniedPreferences,
            scheduler: deniedScheduler,
            scenarioCatalog: scenarioCatalog
        )
        await deniedCoordinator.reconcileNow()
        XCTAssertTrue(deniedScheduler.requests.isEmpty)

        let noRecommendationPreferences = InMemoryPreferences()
        noRecommendationPreferences.workoutReminderSettings = settings(style: .character)
        let noRecommendationScheduler = MemoryWorkoutReminderScheduler()
        let noRecommendationCoordinator = makeCoordinator(
            preferences: noRecommendationPreferences,
            exerciseCatalog: ReminderExerciseCatalog(exercises: []),
            scheduler: noRecommendationScheduler,
            scenarioCatalog: scenarioCatalog
        )
        await noRecommendationCoordinator.reconcileNow()
        XCTAssertTrue(noRecommendationScheduler.requests.isEmpty)
    }

    func testAcknowledgmentUsesCharacterCategoryPrefixAndThreeSecondDelay() async throws {
        let scenarioCatalog = try NotificationScenarioCatalog.bundled()
        let preferences = InMemoryPreferences()
        preferences.workoutReminderSettings = settings(style: .character)
        let record = workout(endedAt: date(2026, 10, 17, hour: 17))
        let history = ReminderHistoryRepository(records: [record])
        let scheduler = MemoryWorkoutReminderScheduler()
        let coordinator = makeCoordinator(
            preferences: preferences,
            workoutHistory: history,
            scheduler: scheduler,
            scenarioCatalog: scenarioCatalog,
            now: { self.date(2026, 10, 17, hour: 17) }
        )
        let acknowledgment = expectation(description: "acknowledgment scheduled")
        scheduler.onScheduleAcknowledgment = { acknowledgment.fulfill() }

        coordinator.workoutSaved(record)
        await fulfillment(of: [acknowledgment], timeout: 2)

        let request = try XCTUnwrap(scheduler.acknowledgments.first)
        XCTAssertEqual(request.identifier,
                       WorkoutAcknowledgmentRequest.identifierPrefix + record.id.uuidString)
        XCTAssertTrue(request.identifier.hasPrefix(WorkoutAcknowledgmentRequest.identifierPrefix))
        XCTAssertEqual(request.delaySeconds, 3)
        XCTAssertEqual(request.categoryIdentifier, NotificationCategory.acknowledgment)
        XCTAssertNotNil(request.imageAssetName)
        XCTAssertNil(WorkoutReminderAppDelegate.workoutTarget(from: [:]))
        XCTAssertNotEqual(WorkoutAcknowledgmentRequest.identifierPrefix,
                          WorkoutReminderScheduleBuilder.identifierPrefix)
        XCTAssertEqual(scheduler.acknowledgmentHistory.count, 1)
    }

    func testAcknowledgmentsAreSkippedForPlainDisabledDeniedAndLaterSameDayWorkout() async throws {
        let scenarioCatalog = try NotificationScenarioCatalog.bundled()
        let first = workout(endedAt: date(2026, 10, 17, hour: 12))
        let second = workout(endedAt: date(2026, 10, 17, hour: 17))

        let plainPreferences = InMemoryPreferences()
        plainPreferences.workoutReminderSettings = settings(style: .plain)
        let plainScheduler = MemoryWorkoutReminderScheduler()
        let plainCoordinator = makeCoordinator(
            preferences: plainPreferences,
            workoutHistory: ReminderHistoryRepository(records: [first]),
            scheduler: plainScheduler,
            scenarioCatalog: scenarioCatalog
        )
        await assertNoAcknowledgmentAfterSave(plainCoordinator, scheduler: plainScheduler, record: first)

        let disabledPreferences = InMemoryPreferences()
        disabledPreferences.workoutReminderSettings = settings(enabled: false, style: .character)
        let disabledScheduler = MemoryWorkoutReminderScheduler()
        let disabledCoordinator = makeCoordinator(
            preferences: disabledPreferences,
            workoutHistory: ReminderHistoryRepository(records: [first]),
            scheduler: disabledScheduler,
            scenarioCatalog: scenarioCatalog
        )
        await assertNoAcknowledgmentAfterSave(disabledCoordinator, scheduler: disabledScheduler, record: first)

        let deniedPreferences = InMemoryPreferences()
        deniedPreferences.workoutReminderSettings = settings(style: .character)
        let deniedScheduler = MemoryWorkoutReminderScheduler(status: .denied)
        let deniedCoordinator = makeCoordinator(
            preferences: deniedPreferences,
            workoutHistory: ReminderHistoryRepository(records: [first]),
            scheduler: deniedScheduler,
            scenarioCatalog: scenarioCatalog
        )
        await assertNoAcknowledgmentAfterSave(deniedCoordinator, scheduler: deniedScheduler, record: first)

        let sameDayPreferences = InMemoryPreferences()
        sameDayPreferences.workoutReminderSettings = settings(style: .character)
        let sameDayScheduler = MemoryWorkoutReminderScheduler()
        let sameDayCoordinator = makeCoordinator(
            preferences: sameDayPreferences,
            workoutHistory: ReminderHistoryRepository(records: [first, second]),
            scheduler: sameDayScheduler,
            scenarioCatalog: scenarioCatalog
        )
        await assertNoAcknowledgmentAfterSave(sameDayCoordinator, scheduler: sameDayScheduler, record: second)
    }

    func testSecondSaveReplacesAcknowledgmentAndReconcileKeepsIt() async throws {
        let scenarioCatalog = try NotificationScenarioCatalog.bundled()
        let preferences = InMemoryPreferences()
        preferences.workoutReminderSettings = settings(style: .character)
        let first = workout(endedAt: date(2026, 10, 17, hour: 17))
        let second = workout(endedAt: date(2026, 10, 18, hour: 17))
        let history = ReminderHistoryRepository(records: [first])
        let scheduler = MemoryWorkoutReminderScheduler()
        var now = first.endedAt
        let coordinator = makeCoordinator(
            preferences: preferences,
            workoutHistory: history,
            scheduler: scheduler,
            scenarioCatalog: scenarioCatalog,
            now: { now }
        )

        let firstAcknowledgment = expectation(description: "first acknowledgment")
        scheduler.onScheduleAcknowledgment = { firstAcknowledgment.fulfill() }
        coordinator.workoutSaved(first)
        await fulfillment(of: [firstAcknowledgment], timeout: 2)

        history.records.append(second)
        now = second.endedAt
        let secondAcknowledgment = expectation(description: "replacement acknowledgment")
        scheduler.onScheduleAcknowledgment = { secondAcknowledgment.fulfill() }
        coordinator.workoutSaved(second)
        await fulfillment(of: [secondAcknowledgment], timeout: 2)
        await coordinator.reconcileNow()

        XCTAssertEqual(scheduler.acknowledgments.count, 1)
        XCTAssertEqual(scheduler.acknowledgments.first?.identifier,
                       WorkoutAcknowledgmentRequest.identifierPrefix + second.id.uuidString)
        XCTAssertEqual(scheduler.acknowledgmentHistory.count, 2)
    }

    func testSavingReplansToRemoveTheCompletedDaysRemainingSlots() async throws {
        let scenarioCatalog = try NotificationScenarioCatalog.bundled()
        let preferences = InMemoryPreferences()
        preferences.workoutReminderSettings = settings(style: .character)
        let history = ReminderHistoryRepository()
        let scheduler = MemoryWorkoutReminderScheduler()
        let now = date(2026, 10, 17, hour: 17)
        let coordinator = makeCoordinator(
            preferences: preferences,
            workoutHistory: history,
            scheduler: scheduler,
            scenarioCatalog: scenarioCatalog,
            now: { now }
        )
        await coordinator.reconcileNow()
        XCTAssertTrue(scheduler.requests.contains { request in
            guard let fireDate = calendar.date(from: request.dateComponents) else { return false }
            return calendar.isDate(fireDate, inSameDayAs: now)
        })

        let record = workout(endedAt: now)
        history.records.append(record)
        let acknowledgment = expectation(description: "save acknowledgment")
        scheduler.onScheduleAcknowledgment = { acknowledgment.fulfill() }
        coordinator.workoutSaved(record)
        await fulfillment(of: [acknowledgment], timeout: 2)

        XCTAssertFalse(scheduler.requests.contains {
            guard let fireDate = calendar.date(from: $0.dateComponents) else { return false }
            return calendar.isDate(fireDate, inSameDayAs: now)
        })
    }

    func testQuickConsecutiveWorkoutSavesStaySerialized() async throws {
        let scenarioCatalog = try NotificationScenarioCatalog.bundled()
        let preferences = InMemoryPreferences()
        preferences.workoutReminderSettings = settings(style: .character)
        let first = workout(endedAt: date(2026, 10, 17, hour: 17))
        let second = workout(endedAt: date(2026, 10, 18, hour: 17))
        let history = ReminderHistoryRepository(records: [first, second])
        let scheduler = MemoryWorkoutReminderScheduler()
        let coordinator = makeCoordinator(
            preferences: preferences,
            workoutHistory: history,
            scheduler: scheduler,
            scenarioCatalog: scenarioCatalog,
            now: { self.date(2026, 10, 18, hour: 17) }
        )
        let acknowledgments = expectation(description: "two saved-workout acknowledgments")
        acknowledgments.expectedFulfillmentCount = 2
        scheduler.onScheduleAcknowledgment = { acknowledgments.fulfill() }

        coordinator.workoutSaved(first)
        coordinator.workoutSaved(second)
        await fulfillment(of: [acknowledgments], timeout: 2)

        XCTAssertEqual(scheduler.replacementHistory.count, 2)
        XCTAssertEqual(scheduler.acknowledgmentHistory.count, 2)
        XCTAssertEqual(scheduler.acknowledgments.count, 1)
        XCTAssertEqual(scheduler.acknowledgments.first?.identifier,
                       WorkoutAcknowledgmentRequest.identifierPrefix + second.id.uuidString)
    }

    private func assertNoAcknowledgmentAfterSave(
        _ coordinator: WorkoutReminderCoordinator,
        scheduler: MemoryWorkoutReminderScheduler,
        record: WorkoutRecord,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let completed = expectation(description: "save and following reconcile complete")
        completed.expectedFulfillmentCount = 2
        scheduler.onReplaceRequests = { completed.fulfill() }

        coordinator.workoutSaved(record)
        coordinator.reconcile()
        await fulfillment(of: [completed], timeout: 2)

        XCTAssertTrue(scheduler.acknowledgments.isEmpty, file: file, line: line)
    }

    private func makeCoordinator(
        preferences: InMemoryPreferences,
        routines: ReminderRoutineRepository? = nil,
        workoutHistory: ReminderHistoryRepository? = nil,
        exerciseCatalog: any ExerciseCatalogProviding = LiveExerciseCatalog(),
        scheduler: MemoryWorkoutReminderScheduler? = nil,
        scenarioCatalog: NotificationScenarioCatalog? = try? NotificationScenarioCatalog.bundled(),
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 0) }
    ) -> WorkoutReminderCoordinator {
        WorkoutReminderCoordinator(
            preferences: preferences,
            routines: routines ?? ReminderRoutineRepository([]),
            workoutHistory: workoutHistory ?? ReminderHistoryRepository(),
            exerciseCatalog: exerciseCatalog,
            router: AppRouter(),
            scheduler: scheduler ?? MemoryWorkoutReminderScheduler(),
            scenarioCatalog: scenarioCatalog,
            now: now,
            calendar: calendar
        )
    }

    private func settings(
        enabled: Bool = true,
        style: WorkoutReminderStyle,
        recurrence: WorkoutReminderRecurrence = .daily,
        hour: Int = 18,
        minute: Int = 0,
        weekdays: Set<Int> = [2, 4, 6]
    ) -> WorkoutReminderSettings {
        WorkoutReminderSettings(
            enabled: enabled,
            style: style,
            recurrence: recurrence,
            hour: hour,
            minute: minute,
            everyOtherDayStartDate: date(2026, 10, 17),
            weekdays: weekdays
        )
    }

    private func exerciseSuggestion() -> String {
        let exercise = exerciseCatalog.exercise(.shoulderPress)!
        return "\(exercise.presentation.shortName) · \(exercise.sets) × \(exercise.targetLabel)"
            + (exercise.perSide ? " / side" : "")
    }

    private func legacyExerciseCopy() -> String {
        let exercise = exerciseCatalog.exercise(.shoulderPress)!
        let target = "\(exercise.sets) × \(exercise.targetLabel)" + (exercise.perSide ? " / side" : "")
        return "How about \(exercise.presentation.shortName)? · \(target)"
    }

    private func firstEverBody(
        for date: Date,
        catalog: NotificationScenarioCatalog
    ) throws -> String {
        let scenario = try XCTUnwrap(catalog.scenario(id: "first-ever-notification"))
        let dayNumber = NotificationCopyPicker.dayNumber(for: date, calendar: calendar)
        let variant = NotificationCopyPicker.variant(
            scenarioID: scenario.id,
            dayNumber: dayNumber,
            slotIndex: 0
        )
        let content = try XCTUnwrap(NotificationContentBuilder.make(
            scenario: scenario,
            variant: variant,
            values: [.suggestion: exerciseSuggestion()]
        ))
        return content.body
    }

    private func workout(endedAt: Date) -> WorkoutRecord {
        WorkoutRecord(
            startedAt: endedAt.addingTimeInterval(-600),
            endedAt: endedAt,
            planName: nil,
            entries: [WorkoutRecordEntry(
                exerciseID: .shoulderPress,
                name: "Shoulder Press",
                outcome: .completed,
                sets: [RecordedSet(reps: 8)]
            )]
        )
    }

    private func routine(_ name: String, exercises ids: [ExerciseID]) -> SavedExerciseSetRecord {
        let set = SavedExerciseSet(name: name, items: ids.map { id in
            let exercise = exerciseCatalog.exercise(id)!
            return SavedExerciseSetItem(
                exerciseID: id,
                setCount: 2,
                targetRepMinimum: exercise.targetReps.lowerBound,
                targetRepMaximum: exercise.targetReps.upperBound
            )
        })
        let date = self.date(2026, 1, 1)
        return SavedExerciseSetRecord(set: set, createdAt: date, updatedAt: date)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}

@MainActor
private final class ReminderRoutineRepository: RoutineRepository {
    private let savedRoutines: [SavedExerciseSetRecord]

    init(_ savedRoutines: [SavedExerciseSetRecord]) {
        self.savedRoutines = savedRoutines
    }

    func list() throws -> [SavedExerciseSet] { savedRoutines.map(\.set) }
    func listWithUpdateDates() throws -> [SavedExerciseSetRecord] { savedRoutines }
    func save(_ set: SavedExerciseSet) throws {}
    func duplicate(_ set: SavedExerciseSet) throws -> SavedExerciseSet { set.duplicated() }
    func delete(id: UUID) throws {}
}

@MainActor
private final class ReminderHistoryRepository: WorkoutHistoryRepository {
    var records: [WorkoutRecord]

    init(records: [WorkoutRecord] = []) {
        self.records = records
    }

    func list() throws -> [WorkoutRecord] { records }

    func save(_ record: WorkoutRecord) throws {
        if !records.contains(where: { $0.id == record.id }) {
            records.append(record)
        }
    }

    func updateWeights(for record: WorkoutRecord) throws {}
    func delete(id: UUID) throws {}
}

private struct ReminderExerciseCatalog: ExerciseCatalogProviding {
    let exercises: [ExerciseDefinition]
    var all: [ExerciseDefinition] { exercises }
    func exercise(_ id: ExerciseID) -> ExerciseDefinition? { exercises.first { $0.id == id } }
}
