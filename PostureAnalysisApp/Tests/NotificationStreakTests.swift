import XCTest
@testable import PostureAnalysisApp

final class NotificationStreakTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }

    private func date(_ day: Int, hour: Int = 12) -> Date { date(2026, 1, day, hour: hour) }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func record(_ day: Int, month: Int = 1, hour: Int = 12) -> WorkoutRecord {
        let endedAt = date(2026, month, day, hour: hour)
        return WorkoutRecord(
            startedAt: endedAt.addingTimeInterval(-600), endedAt: endedAt,
            planName: nil, entries: [WorkoutRecordEntry(
                exerciseID: .shoulderPress, name: "Press", sets: [RecordedSet(reps: 1)]
            )]
        )
    }

    private func settings(
        _ recurrence: WorkoutReminderRecurrence = .daily, weekdays: Set<Int> = Set(1...7),
        start: Date? = nil
    ) -> WorkoutReminderSettings {
        WorkoutReminderSettings(
            enabled: true, recurrence: recurrence, hour: 18, minute: 0,
            everyOtherDayStartDate: start ?? date(2026, 1, 1), weekdays: weekdays
        )
    }

    func testNoRecords() {
        let summary = PlannedDaysStreak.summarize(records: [], settings: settings(), asOf: date(3), calendar: calendar)
        XCTAssertEqual(summary.current, 0)
        XCTAssertEqual(summary.longest, 0)
        XCTAssertNil(summary.daysSinceLastWorkout)
        XCTAssertEqual(summary.totalWorkoutDays, 0)
    }

    func testOnlyNonPlannedDaysDoNotExtendStreak() {
        let weekly = settings(.weekly, weekdays: [2])
        let summary = PlannedDaysStreak.summarize(records: [record(6)], settings: weekly, asOf: date(7), calendar: calendar)
        XCTAssertEqual(summary.totalWorkoutDays, 1)
        XCTAssertEqual(summary.current, 0)
    }

    func testTodayPendingKeepsPriorRunOpen() {
        let summary = PlannedDaysStreak.summarize(
            records: [record(1), record(2)], settings: settings(), asOf: date(3), calendar: calendar
        )
        XCTAssertEqual(summary.current, 2)
        XCTAssertEqual(summary.consecutiveMissedPlannedDays, 0)
        XCTAssertTrue(summary.todayIsPlanned)
        XCTAssertFalse(summary.todayCompleted)
    }

    func testTodayCompletedCountsToday() {
        let summary = PlannedDaysStreak.summarize(
            records: [record(1), record(2), record(3)], settings: settings(), asOf: date(3, hour: 20), calendar: calendar
        )
        XCTAssertEqual(summary.current, 3)
        XCTAssertTrue(summary.todayCompleted)
    }

    func testOneMissedPlannedDayBreaksRun() {
        let summary = PlannedDaysStreak.summarize(
            records: (1...5).map { record($0) }, settings: settings(), asOf: date(7), calendar: calendar
        )
        XCTAssertEqual(summary.consecutiveMissedPlannedDays, 1)
        XCTAssertEqual(summary.brokenRunLength, 5)
        XCTAssertEqual(summary.current, 0)
    }

    func testSeveralMissedDaysAndMultipleRecordsOnOneDay() {
        let records = [record(1), record(2), record(2, hour: 18)]
        let summary = PlannedDaysStreak.summarize(records: records, settings: settings(), asOf: date(5), calendar: calendar)
        XCTAssertEqual(summary.totalWorkoutDays, 2)
        XCTAssertEqual(summary.consecutiveMissedPlannedDays, 2)
        XCTAssertEqual(summary.brokenRunLength, 2)
    }

    func testWeeklyScheduleSkipsUnplannedDaysInStreakAndBrokenRun() {
        let weekly = settings(.weekly, weekdays: [2, 4, 6])
        let completed = [5, 7, 9, 12, 14, 16].map { record($0) }
        let summary = PlannedDaysStreak.summarize(records: completed, settings: weekly, asOf: date(20), calendar: calendar)
        XCTAssertEqual(summary.brokenRunLength, 6)
        XCTAssertEqual(summary.current, 0)
    }

    func testEveryOtherDayScheduleAcrossCalendarDays() {
        let alternate = settings(.everyOtherDay, start: date(2026, 1, 1))
        let completed = [1, 3, 5].map { record($0) }
        let summary = PlannedDaysStreak.summarize(records: completed, settings: alternate, asOf: date(9), calendar: calendar)
        XCTAssertEqual(summary.brokenRunLength, 3)
        XCTAssertEqual(summary.consecutiveMissedPlannedDays, 1)
    }

    func testDSTTransitionKeepsEveryOtherDayCalendarCadence() {
        let alternate = settings(.everyOtherDay, start: date(2026, 3, 7))
        let completed = [record(7, month: 3), record(9, month: 3), record(11, month: 3)]
        let summary = PlannedDaysStreak.summarize(
            records: completed, settings: alternate, asOf: date(2026, 3, 17), calendar: calendar
        )
        XCTAssertEqual(summary.brokenRunLength, 3)
        XCTAssertEqual(calendar.component(.hour, from: completed[1].endedAt), 12)
    }

    func testLongestAndPreviousRecordExcludeOpenRun() {
        let completed = [1, 2, 3, 5, 6].map { record($0) }
        let summary = PlannedDaysStreak.summarize(
            records: completed, settings: settings(), asOf: date(6), calendar: calendar
        )
        XCTAssertEqual(summary.current, 2)
        XCTAssertEqual(summary.longest, 3)
        XCTAssertEqual(summary.previousRecord, 3)
    }

    func testPriorRunLengthSurvivesRestartAndSecondDay() {
        let records = (1...6).map { record($0) } + [record(9), record(10)]
        let afterRestart = PlannedDaysStreak.summarize(
            records: Array(records.dropLast()), settings: settings(), asOf: date(9, hour: 20), calendar: calendar
        )
        let secondDay = PlannedDaysStreak.summarize(
            records: records, settings: settings(), asOf: date(10, hour: 20), calendar: calendar
        )
        XCTAssertEqual(afterRestart.current, 1)
        XCTAssertEqual(afterRestart.priorRunLength, 6)
        XCTAssertEqual(secondDay.current, 2)
        XCTAssertEqual(secondDay.priorRunLength, 6)
    }
}
