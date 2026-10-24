import Foundation
import UserNotifications
import XCTest
@testable import PostureAnalysisApp

/// Extra Personable wired through the reminder coordinator, the scheduler boundary, and the notification delegate.
/// Uses the fixture content catalog (untagged "Title <key>" / "Body <key>" lines) so copy changes never break these tests.
@MainActor
final class PersonaCoordinatorTests: XCTestCase {
    private let calendar = PersonaFixtures.calendar

    // MARK: Gating

    func testWithoutATraceStoreThePersonaStaysOutOfTheWay() async {
        let scheduler = MemoryWorkoutReminderScheduler()
        let coordinator = makeCoordinator(scheduler: scheduler, traces: nil, now: { self.date(day: 17, hour: 10) })

        await coordinator.reconcileNow()

        XCTAssertTrue(scheduler.personaReplacementHistory.isEmpty)
        XCTAssertEqual(scheduler.removeAllPersonaRequestsCount, 0)
        XCTAssertFalse(scheduler.requests.isEmpty, "reminders still schedule")
    }

    func testTurningExtraPersonableOffClearsPersonaRequestsAndKeepsReminders() async {
        let preferences = characterPreferences()
        preferences.extraPersonableEnabled = false
        let scheduler = MemoryWorkoutReminderScheduler()
        let traces = MemoryPersonaTraceStore()
        let coordinator = makeCoordinator(preferences: preferences, scheduler: scheduler, traces: traces,
                                          now: { self.date(day: 17, hour: 10) })

        await coordinator.reconcileNow()

        XCTAssertGreaterThan(scheduler.removeAllPersonaRequestsCount, 0)
        XCTAssertTrue(scheduler.personaReplacementHistory.isEmpty)
        XCTAssertFalse(scheduler.requests.isEmpty)
        XCTAssertEqual(traces.state, .empty)
    }

    func testRemindersOffClearsPersonaRequests() async {
        let preferences = InMemoryPreferences()
        let scheduler = MemoryWorkoutReminderScheduler()
        let coordinator = makeCoordinator(preferences: preferences, scheduler: scheduler, traces: MemoryPersonaTraceStore(),
                                          now: { self.date(day: 17, hour: 10) })

        await coordinator.reconcileNow()

        XCTAssertGreaterThan(scheduler.removeAllPersonaRequestsCount, 0)
    }

    // MARK: Workout save

    func testAHighPRFoldsIntoTheDaysAcknowledgmentInsteadOfASecondNotification() async throws {
        let prior = [1, 5, 9].map { rows(day: $0, lb: 15) }
        let saved = rows(day: 12, lb: 20)
        let history = PersonaHistoryRepository(records: prior + [saved])
        let scheduler = MemoryWorkoutReminderScheduler()
        let traces = MemoryPersonaTraceStore()
        let coordinator = makeCoordinator(history: history, scheduler: scheduler, traces: traces, now: { saved.endedAt })

        let acknowledged = expectation(description: "acknowledgment")
        scheduler.onScheduleAcknowledgment = { acknowledged.fulfill() }
        coordinator.workoutSaved(saved)
        await fulfillment(of: [acknowledged], timeout: 2)

        let acknowledgment = try XCTUnwrap(scheduler.acknowledgments.first)
        XCTAssertEqual(acknowledgment.title, "Title achievement.pr.weight")
        XCTAssertEqual(acknowledgment.categoryIdentifier, NotificationCategory.acknowledgment)
        XCTAssertTrue(scheduler.immediatePersonaRequests.isEmpty, "a fold never sends a second notification")
        let trace = try XCTUnwrap(traces.state.sent.first { $0.observation.contentKey == "achievement.pr.weight" })
        XCTAssertEqual(trace.delivery, .foldedReplace)
        XCTAssertEqual(trace.salience, .high)
    }

    func testAPROnTheDaysSecondWorkoutIsAStandaloneActiveNotification() async throws {
        let prior = [1, 5, 9].map { rows(day: $0, lb: 15) }
        let morning = rows(day: 12, hour: 8, lb: 15)
        let evening = rows(day: 12, hour: 18, lb: 20)
        let history = PersonaHistoryRepository(records: prior + [morning, evening])
        let scheduler = MemoryWorkoutReminderScheduler()
        let traces = MemoryPersonaTraceStore()
        let coordinator = makeCoordinator(history: history, scheduler: scheduler, traces: traces, now: { evening.endedAt })

        let sent = expectation(description: "standalone persona request")
        scheduler.onAddPersonaRequest = { sent.fulfill() }
        coordinator.workoutSaved(evening)
        await fulfillment(of: [sent], timeout: 2)

        let request = try XCTUnwrap(scheduler.immediatePersonaRequests.first)
        XCTAssertEqual(request.interruption, .active)
        XCTAssertEqual(request.categoryIdentifier, NotificationCategory.persona)
        XCTAssertTrue(request.identifier.hasPrefix(PersonaNotificationRequest.immediatePrefix))
        XCTAssertEqual(request.trigger, .after(seconds: 1))
        XCTAssertNotNil(request.userInfo[PersonaNotificationRequest.UserInfoKey.traceID])
        XCTAssertTrue(scheduler.acknowledgments.isEmpty, "only the first workout of a day is acknowledged")
    }

    // MARK: Reconciliation

    func testReconcileProjectsAWeekdayNudgeAsAPassiveRequest() async throws {
        // Four Saturdays in a row (Oct 10, 3, Sep 26, 19); on Saturday Oct 17 morning she nudges toward a fifth.
        let saturdays = [date(day: 10), date(day: 3), date(day: 26, month: 9), date(day: 19, month: 9)]
        let history = PersonaHistoryRepository(records: saturdays.map { PersonaFixtures.record(endingAt: $0) })
        let scheduler = MemoryWorkoutReminderScheduler()
        let traces = MemoryPersonaTraceStore()
        let coordinator = makeCoordinator(history: history, scheduler: scheduler, traces: traces,
                                          now: { self.date(day: 17, hour: 8) })

        await coordinator.reconcileNow()

        let request = try XCTUnwrap(scheduler.personaRequests.first { $0.title == "Title pattern.weekday.upcoming" })
        XCTAssertTrue(request.isProjected)
        XCTAssertEqual(request.interruption, .passive)
        XCTAssertEqual(request.trigger, .at(DateComponents(year: 2026, month: 10, day: 17, hour: 11, minute: 30)))
        XCTAssertTrue(traces.state.sent.contains { $0.identifier == request.identifier })
    }

    func testReconcileReplacesProjectedRequestsButKeepsImmediateOnes() async {
        let scheduler = MemoryWorkoutReminderScheduler()
        let immediate = PersonaNotificationRequest(
            identifier: PersonaNotificationRequest.immediatePrefix + "2026-10-17.x", title: "t", body: "b",
            imageAssetName: nil, categoryIdentifier: NotificationCategory.persona, interruption: .active,
            trigger: .after(seconds: 1), userInfo: [:]
        )
        await scheduler.addPersonaRequest(immediate)
        let coordinator = makeCoordinator(scheduler: scheduler, traces: MemoryPersonaTraceStore(),
                                          now: { self.date(day: 17, hour: 8) })

        await coordinator.reconcileNow()
        await coordinator.reconcileNow()

        XCTAssertEqual(scheduler.personaRequests.filter { $0.identifier == immediate.identifier }.count, 1)
        XCTAssertEqual(scheduler.personaReplacementHistory.count, 2)
    }

    func testOneSaveEvaluatesThePersonaOnceAfterTheReminderReplan() async {
        let prior = [1, 5, 9].map { rows(day: $0, lb: 15) }
        let saved = rows(day: 12, lb: 20)
        let scheduler = MemoryWorkoutReminderScheduler()
        var order: [String] = []
        scheduler.onReplaceRequests = { order.append("reminders") }
        scheduler.onReplacePersonaRequests = { order.append("persona") }
        let coordinator = makeCoordinator(history: PersonaHistoryRepository(records: prior + [saved]), scheduler: scheduler,
                                          traces: MemoryPersonaTraceStore(), now: { saved.endedAt })

        let acknowledged = expectation(description: "acknowledgment")
        scheduler.onScheduleAcknowledgment = { acknowledged.fulfill() }
        coordinator.workoutSaved(saved)
        await fulfillment(of: [acknowledged], timeout: 2)

        XCTAssertEqual(order, ["reminders", "persona"])
    }

    func testQuietHoursDeferAnImmediateMessageWhenTheAppIsInactive() async throws {
        let prior = [1, 5, 9].map { rows(day: $0, lb: 15) }
        let earlier = rows(day: 12, hour: 18, lb: 15)
        let lateNight = PersonaFixtures.record(
            endingAt: PersonaFixtures.date(day: 12, hour: 23),
            entries: [PersonaFixtures.entry(PersonaFixtures.rows, sets: [PersonaFixtures.set(10, lb: 20)])]
        )
        let scheduler = MemoryWorkoutReminderScheduler()
        let traces = MemoryPersonaTraceStore()
        let coordinator = makeCoordinator(history: PersonaHistoryRepository(records: prior + [earlier, lateNight]),
                                          scheduler: scheduler, traces: traces, now: { lateNight.endedAt }, appIsActive: false)

        let sent = expectation(description: "deferred persona request")
        scheduler.onAddPersonaRequest = { sent.fulfill() }
        coordinator.workoutSaved(lateNight)
        await fulfillment(of: [sent], timeout: 2)

        let request = try XCTUnwrap(scheduler.immediatePersonaRequests.first)
        XCTAssertEqual(request.trigger, .at(DateComponents(year: 2026, month: 10, day: 13, hour: 8, minute: 0)))
        XCTAssertTrue(request.identifier.hasPrefix(PersonaNotificationRequest.immediatePrefix + "2026-10-13."))
        XCTAssertTrue(traces.state.sent.contains { $0.quietDeferred && $0.identifier == request.identifier })
    }

    func testTurningOffAfterRequestsExistClearsThemAndTheirPendingTraces() async throws {
        let saturdays = [date(day: 10), date(day: 3), date(day: 26, month: 9), date(day: 19, month: 9)]
        let preferences = characterPreferences()
        var now = date(day: 17, hour: 8)
        let scheduler = MemoryWorkoutReminderScheduler()
        let traces = MemoryPersonaTraceStore()
        let coordinator = makeCoordinator(preferences: preferences,
                                          history: PersonaHistoryRepository(records: saturdays.map { PersonaFixtures.record(endingAt: $0) }),
                                          scheduler: scheduler, traces: traces, now: { now })
        await coordinator.reconcileNow()
        XCTAssertFalse(scheduler.personaRequests.isEmpty)
        XCTAssertTrue(traces.state.sent.contains { $0.isPending(asOf: now) })

        preferences.extraPersonableEnabled = false
        await coordinator.reconcileNow()
        XCTAssertTrue(scheduler.personaRequests.isEmpty)
        XCTAssertFalse(traces.state.sent.contains { $0.isPending(asOf: now) }, "pending traces go with their requests")

        now = date(day: 27, hour: 8)
        preferences.extraPersonableEnabled = true
        XCTAssertEqual(coordinator.personaStatus().cooling, .none, "requests that never fired are not ignored messages")
        XCTAssertEqual(coordinator.personaStatus().pendingCount, 0)
    }

    func testTheBridgeBuffersEngagementUntilTheRecorderIsInstalled() {
        let bridge = WorkoutReminderNotificationBridge()
        let event = PersonaEngagementEvent(traceID: UUID(), observationKey: "k", kind: .dismissed, date: date(day: 17))
        var received: [PersonaEngagementEvent] = []
        bridge.receive(engagement: event)
        bridge.installEngagement { received.append($0) }
        XCTAssertEqual(received, [event])
        bridge.receive(engagement: event)
        XCTAssertEqual(received.count, 2)
    }

    func testOnlyOpeningANotificationRoutesToAWorkout() {
        XCTAssertTrue(WorkoutReminderAppDelegate.shouldRouteToWorkout(actionIdentifier: UNNotificationDefaultActionIdentifier))
        XCTAssertFalse(WorkoutReminderAppDelegate.shouldRouteToWorkout(actionIdentifier: UNNotificationDismissActionIdentifier))
    }

    // MARK: Reset, engagement, status

    func testResetPersonaStartsFamiliarityOverAndKeepsHistoryAndTheSetting() async throws {
        let now = date(day: 17, hour: 10)
        let history = PersonaHistoryRepository(records: PersonaFixtures.workouts(onOctoberDays: Array(1...16)))
        let scheduler = MemoryWorkoutReminderScheduler()
        let traces = MemoryPersonaTraceStore(state: PersonaTraceState(engagement: [
            PersonaEngagementEvent(traceID: UUID(), observationKey: "k", kind: .dismissed, date: now.addingTimeInterval(-60)),
        ]))
        let preferences = characterPreferences()
        let coordinator = makeCoordinator(preferences: preferences, history: history, scheduler: scheduler, traces: traces,
                                          now: { now })
        XCTAssertEqual(coordinator.personaStatus().familiarity, .established)

        await coordinator.resetPersona()

        XCTAssertEqual(preferences.personaResetDate, now)
        XCTAssertTrue(preferences.extraPersonableEnabled)
        XCTAssertTrue(traces.state.engagement.isEmpty)
        XCTAssertGreaterThan(scheduler.removeAllPersonaRequestsCount, 0)
        XCTAssertEqual(try history.list().count, 16, "history is untouched")
        XCTAssertEqual(coordinator.personaStatus().familiarity, .new)
    }

    func testEngagementIsRecordedAsAFrequencySignal() {
        let traces = MemoryPersonaTraceStore()
        let coordinator = makeCoordinator(traces: traces, now: { self.date(day: 17) })
        let event = PersonaEngagementEvent(traceID: UUID(), observationKey: "pattern.weekday.7.2026-W42", kind: .tapped,
                                           date: date(day: 17))

        coordinator.recordPersonaEngagement(event)

        XCTAssertEqual(traces.state.engagement, [event])
    }

    func testStatusReportsTheCapQuietHoursAndActivity() {
        let coordinator = makeCoordinator(traces: MemoryPersonaTraceStore(), now: { self.date(day: 17, hour: 23) })

        let status = coordinator.personaStatus()

        XCTAssertTrue(status.isActive)
        XCTAssertEqual(status.dailyCap, 2)
        XCTAssertEqual(status.standaloneCountToday, 0)
        XCTAssertTrue(status.isQuietNow)
        XCTAssertEqual(status.quietHoursSummary, "22:00–08:00")
    }

    // MARK: Delivery boundary

    func testThePersonaCategoryReportsDismissalsAndOthersDoNot() throws {
        let categories = NotificationCategoryRegistrar.categories()
        let persona = try XCTUnwrap(categories.first { $0.identifier == NotificationCategory.persona })
        XCTAssertTrue(persona.options.contains(.customDismissAction))
        XCTAssertTrue(categories.filter { $0.identifier != NotificationCategory.persona }
            .allSatisfy { !$0.options.contains(.customDismissAction) })
    }

    func testPersonaTapsAndDismissalsBecomeEngagementEvents() {
        let traceID = UUID()
        let userInfo: [AnyHashable: Any] = [
            PersonaNotificationRequest.UserInfoKey.traceID: traceID.uuidString,
            PersonaNotificationRequest.UserInfoKey.observationKey: "lapse.comeback.-.2026-10-17",
        ]
        let date = date(day: 17)

        let tap = WorkoutReminderAppDelegate.personaEngagement(
            categoryIdentifier: NotificationCategory.persona, actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: userInfo, date: date
        )
        let dismiss = WorkoutReminderAppDelegate.personaEngagement(
            categoryIdentifier: NotificationCategory.persona, actionIdentifier: UNNotificationDismissActionIdentifier,
            userInfo: userInfo, date: date
        )
        let reminder = WorkoutReminderAppDelegate.personaEngagement(
            categoryIdentifier: NotificationCategory.nudge, actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: userInfo, date: date
        )

        XCTAssertEqual(tap, PersonaEngagementEvent(traceID: traceID, observationKey: "lapse.comeback.-.2026-10-17", kind: .tapped, date: date))
        XCTAssertEqual(dismiss?.kind, .dismissed)
        XCTAssertNil(reminder)
    }

    func testPassivePersonaNotificationsShowSilentlyWhileTheAppIsOpen() {
        XCTAssertEqual(
            WorkoutReminderAppDelegate.foregroundPresentation(forCategory: NotificationCategory.persona, interruptionLevel: .passive),
            [.banner, .list]
        )
        XCTAssertEqual(
            WorkoutReminderAppDelegate.foregroundPresentation(forCategory: NotificationCategory.persona, interruptionLevel: .active),
            [.banner, .list, .sound]
        )
        XCTAssertEqual(WorkoutReminderAppDelegate.foregroundPresentation(forCategory: NotificationCategory.nudge), [])
        XCTAssertEqual(UserNotificationWorkoutReminderScheduler.interruptionLevel(for: .passive), .passive)
        XCTAssertEqual(UserNotificationWorkoutReminderScheduler.interruptionLevel(for: .active), .active)
    }

    // MARK: Helpers

    private func makeCoordinator(
        preferences: InMemoryPreferences? = nil,
        history: PersonaHistoryRepository? = nil,
        scheduler: MemoryWorkoutReminderScheduler? = nil,
        traces: MemoryPersonaTraceStore?,
        now: @escaping () -> Date,
        appIsActive: Bool = true
    ) -> WorkoutReminderCoordinator {
        WorkoutReminderCoordinator(
            preferences: preferences ?? characterPreferences(),
            routines: nil,
            workoutHistory: history ?? PersonaHistoryRepository(),
            exerciseCatalog: LiveExerciseCatalog(),
            router: AppRouter(),
            scheduler: scheduler ?? MemoryWorkoutReminderScheduler(),
            scenarioCatalog: try? NotificationScenarioCatalog.bundled(),
            now: now,
            calendar: calendar,
            personaCatalog: PersonaFixtures.catalog(),
            personaTraces: traces,
            isAppActive: { appIsActive }
        )
    }

    /// Character reminders on at 18:00 daily, far from the 11:30 persona slot.
    private func characterPreferences() -> InMemoryPreferences {
        let preferences = InMemoryPreferences()
        var settings = PersonaFixtures.reminderSettings
        settings.hour = 18
        preferences.workoutReminderSettings = settings
        return preferences
    }

    private func rows(day: Int, hour: Int = 12, lb: Double) -> WorkoutRecord {
        PersonaFixtures.record(
            endingAt: date(day: day, hour: hour),
            entries: [PersonaFixtures.entry(PersonaFixtures.rows, sets: [PersonaFixtures.set(10, lb: lb)])]
        )
    }

    private func date(day: Int, month: Int = 10, hour: Int = 12) -> Date {
        PersonaFixtures.date(day: day, month: month, hour: hour)
    }
}

@MainActor
private final class PersonaHistoryRepository: WorkoutHistoryRepository {
    var records: [WorkoutRecord]

    init(records: [WorkoutRecord] = []) {
        self.records = records
    }

    func list() throws -> [WorkoutRecord] { records.sorted { $0.endedAt > $1.endedAt } }
    func save(_ record: WorkoutRecord) throws { records.append(record) }
    func updateWeights(for record: WorkoutRecord) throws {}
    func delete(id: UUID) throws {}
}
