import XCTest
@testable import PostureAnalysisApp

final class NotificationPlannerTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }

    private func date(_ day: Int, hour: Int = 8) -> Date { date(2026, 10, day, hour: hour) }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 8) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func record(_ day: Int, month: Int = 10, year: Int = 2026, hour: Int = 12) -> WorkoutRecord {
        let end = date(year, month, day, hour: hour)
        return WorkoutRecord(
            startedAt: end.addingTimeInterval(-600), endedAt: end, planName: nil,
            entries: [WorkoutRecordEntry(exerciseID: .shoulderPress, name: "Press", sets: [RecordedSet(reps: 1)])]
        )
    }

    private func settings(
        enabled: Bool = true, hour: Int = 18, minute: Int = 0,
        recurrence: WorkoutReminderRecurrence = .daily, weekdays: Set<Int> = [2, 4, 6],
        start: Date? = nil
    ) -> WorkoutReminderSettings {
        WorkoutReminderSettings(
            enabled: enabled, recurrence: recurrence, hour: hour, minute: minute,
            everyOtherDayStartDate: start ?? date(2026, 10, 1), weekdays: weekdays
        )
    }

    private func catalog() throws -> NotificationScenarioCatalog {
        try NotificationScenarioCatalog.bundled(bundle: Bundle(for: AppEnvironment.self))
    }

    private func plan(
        records: [WorkoutRecord] = [], settings: WorkoutReminderSettings? = nil, now: Date,
        firstEver: Bool = false, policy: NotificationPolicy = .standard
    ) throws -> [PlannedNotification] {
        NotificationPlanner.plan(
            records: records, settings: settings ?? self.settings(), now: now, calendar: calendar,
            suggestion: "Workout", isFirstEverNotification: firstEver, catalog: try catalog(), policy: policy
        )
    }

    func testDisabledReturnsNoRequests() throws {
        XCTAssertTrue(try plan(settings: settings(enabled: false), now: date(17)).isEmpty)
    }

    func testCompletedTodayIsSkipped() throws {
        let planned = try plan(records: [record(17, hour: 7)], now: date(17))
        XCTAssertFalse(planned.contains { $0.fireDate.day == 17 && $0.fireDate.month == 10 })
    }

    func testSlotScheduleCapsFollowUpAtTwentyOneAndEnforcesGaps() {
        let normal = NotificationSlotSchedule.slots(
            day: date(18), settings: settings(hour: 18, minute: 30), calendar: calendar
        )
        XCTAssertEqual(normal.map(\.slot), [.reminder, .followUp, .finalWarning])
        XCTAssertEqual(normal.map { calendar.component(.hour, from: $0.time) }, [18, 21, 21])
        XCTAssertEqual(normal.map { calendar.component(.minute, from: $0.time) }, [30, 0, 30])
        XCTAssertLessThanOrEqual(normal[1].time, date(18, hour: 21))

        let tooCloseToReminder = NotificationSlotSchedule.slots(
            day: date(18), settings: settings(hour: 20, minute: 45), calendar: calendar
        )
        XCTAssertEqual(tooCloseToReminder.map(\.slot), [.reminder, .finalWarning])
        let tooCloseToFinal = NotificationSlotSchedule.slots(
            day: date(18), settings: settings(hour: 21, minute: 10), calendar: calendar
        )
        XCTAssertEqual(tooCloseToFinal.map(\.slot), [.reminder])
    }

    func testAtMostThreeRequestsPerDayAndSorted() throws {
        let notifications = try plan(records: [record(16)], now: date(17))
        let dayCounts = Dictionary(grouping: notifications, by: { "\($0.fireDate.year!)-\($0.fireDate.month!)-\($0.fireDate.day!)" })
        XCTAssertTrue(dayCounts.values.allSatisfy { $0.count <= 3 })
        let times = notifications.compactMap { calendar.date(from: $0.fireDate) }
        XCTAssertEqual(times, times.sorted())
    }

    func testMaximumRequestCapCanBeReachedWithExtendedPolicy() throws {
        let longerPolicy = NotificationPolicy(
            recentHistoryDays: 100, stopAfterDaysWithoutWorkout: 100,
            taperAfterMissedPlannedDays: 100, planningHorizonPlannedDays: 30,
            maximumRequests: 60
        )
        let notifications = try plan(
            records: [record(16)], now: date(17), policy: longerPolicy
        )
        XCTAssertEqual(notifications.count, 60)
    }

    func testProjectionBreaksAStreakOnFirstAndSecondMissedDays() throws {
        let notifications = try plan(records: (1...12).map { record($0) }, now: date(13))
        let reminderScenarios = Dictionary(uniqueKeysWithValues: notifications.filter { $0.slot == .reminder }
            .compactMap { item in item.fireDate.day.map { ($0, item.scenarioID) } })
        XCTAssertEqual(reminderScenarios[14], "streak-broken")
        XCTAssertEqual(reminderScenarios[15], "immediate-post-break")
    }

    func testThreeMissedDaysTaperToReminderOnly() throws {
        let notifications = try plan(records: [record(1)], now: date(2))
        let dayFive = notifications.filter { $0.fireDate.day == 5 }
        XCTAssertEqual(dayFive.count, 1)
        XCTAssertEqual(dayFive.first?.slot, .reminder)
    }

    func testFourteenDaysWithoutWorkoutStopsPlanning() throws {
        XCTAssertTrue(try plan(records: [record(1)], now: date(15)).isEmpty)
    }

    func testFirstEverIsAppliedOnceAndIdentifiersAreUnique() throws {
        let notifications = try plan(records: [record(16)], now: date(17), firstEver: true)
        XCTAssertEqual(notifications.filter { $0.scenarioID == "first-ever-notification" }.count, 1)
        XCTAssertEqual(Set(notifications.map(\.identifier)).count, notifications.count)
    }

    func testDailyWeeklyAndEveryOtherDaySchedules() throws {
        let daily = try plan(records: [record(16)], settings: settings(recurrence: .daily), now: date(17))
        XCTAssertTrue(daily.contains { $0.fireDate.day == 17 })
        let weeklySettings = settings(recurrence: .weekly, weekdays: [2])
        let weekly = try plan(records: [record(16)], settings: weeklySettings, now: date(17))
        XCTAssertTrue(weekly.allSatisfy { $0.fireDate.day == 19 || $0.fireDate.day == 26 })
        let alternateSettings = settings(recurrence: .everyOtherDay, start: date(2026, 10, 17))
        let alternate = try plan(records: [record(16)], settings: alternateSettings, now: date(17))
        XCTAssertTrue(alternate.allSatisfy { (($0.fireDate.day ?? 0) - 17).isMultiple(of: 2) })
    }

    func testDSTTransitionKeepsLocalSlotTimes() throws {
        let notifications = try plan(
            records: [record(7, month: 3)], settings: settings(hour: 18, minute: 30),
            now: date(2026, 3, 8, hour: 8)
        )
        let transitionDay = notifications.filter { $0.fireDate.month == 3 && $0.fireDate.day == 8 }
        XCTAssertEqual(transitionDay.first?.fireDate.hour, 18)
        XCTAssertEqual(transitionDay.first?.fireDate.minute, 30)
        XCTAssertNil(transitionDay.first?.fireDate.timeZone)
    }
}
