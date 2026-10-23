import XCTest
@testable import PostureAnalysisApp

final class NotificationSelectorTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }

    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour))!
    }

    private func record(_ day: Int, hour: Int = 12, month: Int = 1) -> WorkoutRecord {
        let end = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
        return WorkoutRecord(
            startedAt: end.addingTimeInterval(-600), endedAt: end, planName: nil,
            entries: [WorkoutRecordEntry(exerciseID: .shoulderPress, name: "Press", sets: [RecordedSet(reps: 1)])]
        )
    }

    private func settings(
        hour: Int = 18, recurrence: WorkoutReminderRecurrence = .daily,
        weekdays: Set<Int> = Set(1...7)
    ) -> WorkoutReminderSettings {
        WorkoutReminderSettings(
            enabled: true, recurrence: recurrence, hour: hour, minute: 0,
            everyOtherDayStartDate: date(1), weekdays: weekdays
        )
    }

    private func run(_ start: Int, _ length: Int, hour: Int = 12) -> [WorkoutRecord] {
        (start..<(start + length)).map { record($0, hour: hour) }
    }

    private func nudge(
        _ expected: String, records: [WorkoutRecord], day: Int, slot: NotificationSlot = .reminder,
        settings: WorkoutReminderSettings? = nil, firstEver: Bool = false
    ) -> NotificationSelection {
        let activeSettings = settings ?? self.settings()
        let slotTime = NotificationSlotSchedule.slots(
            day: date(day), settings: activeSettings, calendar: calendar
        ).first(where: { $0.slot == slot })?.time ?? date(day, hour: 21)
        let facts = NotificationScenarioSelector.nudgeFacts(
            day: date(day), slot: slot, slotTime: slotTime, records: records,
            settings: activeSettings, isFirstEverNotification: firstEver, calendar: calendar
        )
        let result = NotificationScenarioSelector.select(nudge: facts)
        XCTAssertEqual(result.scenarioID, expected)
        let catalog = try? NotificationScenarioCatalog.bundled(bundle: Bundle(for: AppEnvironment.self))
        XCTAssertNotNil(catalog?.scenario(id: result.scenarioID))
        return result
    }

    private func acknowledgment(_ expected: String, records: [WorkoutRecord], latest: WorkoutRecord,
                                settings: WorkoutReminderSettings? = nil) -> NotificationSelection {
        let selected = NotificationScenarioSelector.acknowledgment(
            for: latest, records: records, settings: settings ?? self.settings(), calendar: calendar
        )
        XCTAssertEqual(selected?.scenarioID, expected)
        let catalog = try? NotificationScenarioCatalog.bundled(bundle: Bundle(for: AppEnvironment.self))
        if let selected { XCTAssertNotNil(catalog?.scenario(id: selected.scenarioID)) }
        return selected ?? NotificationSelection(scenarioID: "missing", values: [:])
    }

    func testFirstEverNotification() { nudge("first-ever-notification", records: [], day: 20, firstEver: true) }
    func testStreakBroken() {
        let result = nudge("streak-broken", records: run(1, 5), day: 7)
        XCTAssertEqual(result.values[.streak], "5")
    }
    func testImmediatePostBreak() { nudge("immediate-post-break", records: run(1, 5), day: 8) }
    func testLongAbsence() {
        let result = nudge("long-absence", records: [record(1)], day: 9)
        XCTAssertEqual(result.values[.days], "8")
    }
    func testNeverEstablishedHistory() { nudge("never-established-history", records: [], day: 20) }
    func testLateNightReminder() {
        let result = nudge("late-night-reminder", records: [record(2)], day: 3, settings: settings(hour: 21))
        XCTAssertNil(result.values[.streak])
    }
    func testLateNightStreakAtRisk() {
        let result = nudge("late-night-streak-at-risk", records: run(1, 5), day: 6, settings: settings(hour: 21))
        XCTAssertEqual(result.values[.streak], "5")
    }
    func testApproachingPersonalBest() {
        let records = run(1, 7) + run(9, 5)
        let result = nudge("approaching-personal-best", records: records, day: 14)
        XCTAssertEqual(result.values[.streak], "5")
        XCTAssertEqual(result.values[.record], "7")
        XCTAssertEqual(result.values[.remaining], "3")
    }
    func testAlmostOneWeek() { nudge("almost-one-week", records: run(1, 6), day: 7) }
    func testEstablishedStreakReminder() { nudge("established-streak-reminder", records: run(1, 5), day: 6) }
    func testEarlyStreakForming() { nudge("early-streak-forming", records: run(1, 3), day: 4) }
    func testNeutralCheckIn() {
        let records = [record(1), record(2), record(3)]
        nudge("neutral-check-in", records: records, day: 5)
    }
    func testMorningReminder() { nudge("morning-reminder", records: [record(2)], day: 3, settings: settings(hour: 9)) }
    func testWeekendReminder() { nudge("weekend-reminder", records: [record(2)], day: 4) }
    func testOrdinaryDailyReminder() { nudge("ordinary-daily-reminder", records: [record(4)], day: 5) }
    func testEstablishedStreakAtRisk() { nudge("established-streak-at-risk", records: run(1, 5), day: 6, slot: .followUp, settings: settings(hour: 17)) }
    func testHighValueStreakAtRisk() { nudge("high-value-streak-at-risk", records: run(1, 21), day: 22, slot: .followUp, settings: settings(hour: 17)) }
    func testFirstIgnoredReminder() { nudge("first-ignored-reminder", records: [record(5)], day: 6, slot: .followUp, settings: settings(hour: 17)) }
    func testRepeatedIgnoredReminder() { nudge("repeated-ignored-reminder", records: [record(5)], day: 6, slot: .finalWarning) }
    func testFinalStreakWarning() { nudge("final-streak-warning", records: run(1, 5), day: 6, slot: .finalWarning) }
    func testStrongRepeatedDismissal() {
        let records = run(1, 5, hour: 22)
        nudge("strong-repeated-dismissal", records: records, day: 6, slot: .finalWarning)
    }
    func testRareEscalation() {
        let day = (40...60).first { NotificationCopyPicker.dayNumber(for: date($0), calendar: calendar).isMultiple(of: 5) }!
        nudge("rare-escalation", records: run(day - 30, 30), day: day, slot: .finalWarning)
    }

    func testFirstCompletedSession() {
        let latest = record(1)
        acknowledgment("first-completed-session", records: [latest], latest: latest)
    }
    func testNewPersonalBestStreak() {
        let latestRun = run(9, 8)
        let records = run(1, 7) + latestRun
        let result = acknowledgment("new-personal-best-streak", records: records, latest: latestRun.last!)
        XCTAssertEqual(result.values[.record], "7")
        XCTAssertEqual(result.values[.streak], "8")
    }
    func testMajorStreakMilestone() {
        let latestRun = run(17, 14)
        let records = run(1, 14) + latestRun
        let result = acknowledgment("major-streak-milestone", records: records, latest: latestRun.last!)
        XCTAssertEqual(result.values[.streak], "14")
    }
    func testOneWeekMilestone() {
        let latestRun = run(1, 7)
        acknowledgment("one-week-milestone", records: latestRun, latest: latestRun.last!)
    }
    func testComebackAfterLongAbsence() {
        let records = [record(1), record(10)]
        acknowledgment("comeback-after-long-absence", records: records, latest: records.last!)
    }
    func testRestartAfterBrokenStreak() {
        let records = run(1, 6) + [record(9)]
        acknowledgment("restart-after-broken-streak", records: records, latest: records.last!)
    }
    func testSecondDayAfterRestart() {
        let records = run(1, 6) + [record(9), record(10)]
        acknowledgment("second-day-after-restart", records: records, latest: records.last!)
    }
    func testStreakPreservedLastMinute() {
        let latest = record(6, hour: 21)
        acknowledgment("streak-preserved-last-minute", records: run(1, 5) + [latest], latest: latest)
    }
    func testPerfectWeek() {
        let weekly = settings(recurrence: .weekly, weekdays: [2, 4, 6])
        let records = [record(5), record(7), record(9)]
        acknowledgment("perfect-week", records: records, latest: records.last!, settings: weekly)
    }
    func testWeeklyRecovery() {
        let weekly = settings(recurrence: .weekly, weekdays: [2, 4, 6])
        let records = [record(7), record(9)]
        acknowledgment("weekly-recovery", records: records, latest: records.last!, settings: weekly)
    }
    func testSessionCompletedAfterReminders() {
        let latest = record(6, hour: 20)
        acknowledgment("session-completed-after-reminders", records: [record(5), latest], latest: latest)
    }
    func testNotificationFreeSuccess() {
        let records = [record(2, hour: 8), record(3, hour: 8), record(4, hour: 8), record(5, hour: 8)]
        acknowledgment("notification-free-success", records: records, latest: records.last!)
    }
    func testSessionCompleted() {
        let records = [record(5), record(6, hour: 12)]
        acknowledgment("session-completed", records: records, latest: records.last!)
    }

    func testSelectorOrderingAndCatalogCoverage() throws {
        let catalog = try NotificationScenarioCatalog.bundled(bundle: Bundle(for: AppEnvironment.self))
        XCTAssertEqual(catalog.scenarios.count, 35)
        XCTAssertEqual(catalog.scenarios.filter { $0.kind == .nudge }.count, 22)
        XCTAssertEqual(catalog.scenarios.filter { $0.kind == .acknowledgment }.count, 13)
        for scenario in catalog.scenarios { XCTAssertNotNil(catalog.scenario(id: scenario.id)) }
        let late = NotificationSlotSchedule.slots(day: date(6), settings: settings(hour: 21), calendar: calendar)[0].time
        let facts = NotificationScenarioSelector.nudgeFacts(
            day: date(6), slot: .reminder, slotTime: late, records: run(1, 5), settings: settings(hour: 21),
            isFirstEverNotification: true, calendar: calendar
        )
        XCTAssertEqual(NotificationScenarioSelector.select(nudge: facts).scenarioID, "first-ever-notification")
        let overlappingBreak = PlannedDaysStreak(
            current: 0, longest: 5, previousRecord: 5, totalWorkoutDays: 5,
            lastWorkoutDay: date(1), daysSinceLastWorkout: 9, consecutiveMissedPlannedDays: 1,
            brokenRunLength: 5, priorRunLength: 5, todayIsPlanned: true, todayCompleted: false
        )
        let firstEverBreakFacts = NudgeFacts(
            slot: .reminder, summary: overlappingBreak, isFirstEverNotification: true,
            lateNight: true, hasRecentHistory: true, habitualIgnorer: true, dayNumber: 1,
            recentConsistency: 0, isWeekend: false, reminderHour: 18
        )
        XCTAssertEqual(
            NotificationScenarioSelector.select(nudge: firstEverBreakFacts).scenarioID,
            "first-ever-notification"
        )
    }

    func testReminderRuleOrderingForOverlappingFacts() {
        let openRecordStreak = PlannedDaysStreak(
            current: 5, longest: 7, previousRecord: 7, totalWorkoutDays: 12,
            lastWorkoutDay: date(5), daysSinceLastWorkout: 1, consecutiveMissedPlannedDays: 0,
            brokenRunLength: 0, priorRunLength: 0, todayIsPlanned: true, todayCompleted: false
        )
        let lateApproaching = NudgeFacts(
            slot: .reminder, summary: openRecordStreak, isFirstEverNotification: false,
            lateNight: true, hasRecentHistory: true, habitualIgnorer: false, dayNumber: 5,
            recentConsistency: 0, isWeekend: false, reminderHour: 18
        )
        XCTAssertEqual(NotificationScenarioSelector.select(nudge: lateApproaching).scenarioID, "late-night-streak-at-risk")

        let brokenAndAbsent = PlannedDaysStreak(
            current: 0, longest: 5, previousRecord: 5, totalWorkoutDays: 5,
            lastWorkoutDay: date(1), daysSinceLastWorkout: 9, consecutiveMissedPlannedDays: 1,
            brokenRunLength: 5, priorRunLength: 5, todayIsPlanned: true, todayCompleted: false
        )
        let brokenFacts = NudgeFacts(
            slot: .reminder, summary: brokenAndAbsent, isFirstEverNotification: false,
            lateNight: false, hasRecentHistory: true, habitualIgnorer: false, dayNumber: 1,
            recentConsistency: 0, isWeekend: false, reminderHour: 18
        )
        XCTAssertEqual(NotificationScenarioSelector.select(nudge: brokenFacts).scenarioID, "streak-broken")

        let highValueFacts = NudgeFacts(
            slot: .followUp, summary: openRecordStreak.withCurrent(21), isFirstEverNotification: false,
            lateNight: false, hasRecentHistory: true, habitualIgnorer: false, dayNumber: 1,
            recentConsistency: 0, isWeekend: false, reminderHour: 18
        )
        XCTAssertEqual(NotificationScenarioSelector.select(nudge: highValueFacts).scenarioID, "high-value-streak-at-risk")

        let rareFacts = NudgeFacts(
            slot: .finalWarning, summary: openRecordStreak.withCurrent(30), isFirstEverNotification: false,
            lateNight: true, hasRecentHistory: true, habitualIgnorer: true, dayNumber: 5,
            recentConsistency: 0, isWeekend: false, reminderHour: 18
        )
        XCTAssertEqual(NotificationScenarioSelector.select(nudge: rareFacts).scenarioID, "rare-escalation")
        let habitualFacts = NudgeFacts(
            slot: .finalWarning, summary: openRecordStreak.withCurrent(30), isFirstEverNotification: false,
            lateNight: true, hasRecentHistory: true, habitualIgnorer: true, dayNumber: 6,
            recentConsistency: 0, isWeekend: false, reminderHour: 18
        )
        XCTAssertEqual(NotificationScenarioSelector.select(nudge: habitualFacts).scenarioID, "strong-repeated-dismissal")
        let ordinaryFinalFacts = NudgeFacts(
            slot: .finalWarning, summary: openRecordStreak, isFirstEverNotification: false,
            lateNight: true, hasRecentHistory: true, habitualIgnorer: false, dayNumber: 6,
            recentConsistency: 0, isWeekend: false, reminderHour: 18
        )
        XCTAssertEqual(NotificationScenarioSelector.select(nudge: ordinaryFinalFacts).scenarioID, "final-streak-warning")
    }

    func testNudgeAndAcknowledgmentIdsStayInTheirCatalogKinds() throws {
        let catalog = try NotificationScenarioCatalog.bundled(bundle: Bundle(for: AppEnvironment.self))
        let nudgeIDs: Set<String> = [
            "never-established-history", "first-ever-notification", "ordinary-daily-reminder",
            "neutral-check-in", "early-streak-forming", "almost-one-week", "established-streak-reminder",
            "established-streak-at-risk", "high-value-streak-at-risk", "first-ignored-reminder",
            "repeated-ignored-reminder", "strong-repeated-dismissal", "late-night-reminder",
            "late-night-streak-at-risk", "final-streak-warning", "rare-escalation", "streak-broken",
            "immediate-post-break", "long-absence", "approaching-personal-best", "morning-reminder", "weekend-reminder"
        ]
        let acknowledgmentIDs: Set<String> = [
            "one-week-milestone", "session-completed", "session-completed-after-reminders",
            "streak-preserved-last-minute", "restart-after-broken-streak", "second-day-after-restart",
            "comeback-after-long-absence", "new-personal-best-streak", "major-streak-milestone",
            "perfect-week", "weekly-recovery", "first-completed-session", "notification-free-success"
        ]
        XCTAssertEqual(nudgeIDs.count, 22)
        XCTAssertEqual(acknowledgmentIDs.count, 13)
        XCTAssertEqual(nudgeIDs.union(acknowledgmentIDs), Set(catalog.scenarios.map(\.id)))
        for scenario in catalog.scenarios {
            if nudgeIDs.contains(scenario.id) { XCTAssertEqual(scenario.kind, .nudge) }
            if acknowledgmentIDs.contains(scenario.id) { XCTAssertEqual(scenario.kind, .acknowledgment) }
        }
    }

    func testAcknowledgmentOnlyForFirstWorkoutAndEnabledSettings() {
        let prior = record(5)
        let later = record(5, hour: 18)
        XCTAssertNil(NotificationScenarioSelector.acknowledgment(
            for: later, records: [prior, later], settings: settings(), calendar: calendar
        ))
        XCTAssertNil(NotificationScenarioSelector.acknowledgment(
            for: prior, records: [prior], settings: settings().withEnabled(false), calendar: calendar
        ))
    }
}

private extension WorkoutReminderSettings {
    func withEnabled(_ enabled: Bool) -> WorkoutReminderSettings {
        var copy = self
        copy.enabled = enabled
        return copy
    }
}

private extension PlannedDaysStreak {
    func withCurrent(_ value: Int) -> PlannedDaysStreak {
        PlannedDaysStreak(
            current: value, longest: max(longest, value), previousRecord: previousRecord,
            totalWorkoutDays: totalWorkoutDays, lastWorkoutDay: lastWorkoutDay,
            daysSinceLastWorkout: daysSinceLastWorkout,
            consecutiveMissedPlannedDays: consecutiveMissedPlannedDays,
            brokenRunLength: brokenRunLength, priorRunLength: priorRunLength,
            todayIsPlanned: todayIsPlanned, todayCompleted: todayCompleted
        )
    }
}
