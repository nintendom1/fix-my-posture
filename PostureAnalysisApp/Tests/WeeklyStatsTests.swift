import XCTest
@testable import PostureAnalysisApp

final class WeeklyStatsTests: XCTestCase {
    private var calendar: Calendar { FixedClock.calendar }

    func testMondayStartIncludesMondayAndExcludesSundayNightFromFollowingWeek() {
        let monday = date(2026, 10, 12, hour: 0)
        let sundayBefore = date(2026, 10, 11, hour: 23, minute: 59)
        let sundayAfter = date(2026, 10, 18, hour: 23, minute: 59)
        let records = [
            record(start: monday, durationMinutes: 10, name: "Monday"),
            record(start: sundayBefore, durationMinutes: 20, name: "Last Sunday"),
            record(start: sundayAfter, durationMinutes: 30, name: "Next Sunday")
        ]

        let stats = WeeklyStats(records: records, now: FixedClock.date, calendar: calendar)

        XCTAssertEqual(stats.workouts.map(\.planName), ["Next Sunday", "Monday"])
        XCTAssertEqual(stats.workoutCount, 2)
    }

    func testSumsTimeFromRecordStartAndEndDates() {
        let records = [
            record(start: date(2026, 10, 14, hour: 10), durationMinutes: 26, name: "Upper Body"),
            record(start: date(2026, 10, 12, hour: 10), durationMinutes: 18, name: "Quick Strength")
        ]

        let stats = WeeklyStats(records: records, now: FixedClock.date, calendar: calendar)

        XCTAssertEqual(stats.durationLabel, "44m")
    }

    func testEmptyWeekHasZeroTotalsAndNoRecentWorkouts() {
        let stats = WeeklyStats(records: [], now: FixedClock.date, calendar: calendar)

        XCTAssertTrue(stats.workouts.isEmpty)
        XCTAssertEqual(stats.workoutCount, 0)
        XCTAssertEqual(stats.setCount, 0)
        XCTAssertEqual(stats.repCount, 0)
        XCTAssertEqual(stats.durationLabel, "0m")
        XCTAssertTrue(stats.recent.isEmpty)
    }

    func testCurrentDayIndexUsesInjectedMondayFirstCalendar() {
        let stats = WeeklyStats(records: [], now: FixedClock.date, calendar: calendar)

        XCTAssertEqual(stats.todayIndex, 4)
    }

    func testRecentWorkoutsAreNewestFirstAndLimitedToThree() {
        let records = (0..<4).map { index in
            record(start: date(2026, 10, 12 + index, hour: 10), durationMinutes: 5, name: "Workout \(index)")
        }

        let stats = WeeklyStats(records: records, now: FixedClock.date, calendar: calendar)

        XCTAssertEqual(stats.recent.map(\.name), ["Workout 3", "Workout 2", "Workout 1"])
    }

    func testRecentMetaUsesCompletionStatsForDurationSetsAndReps() {
        let workout = WorkoutRecord(
            startedAt: date(2026, 10, 14, hour: 10),
            endedAt: date(2026, 10, 14, hour: 10).addingTimeInterval(26 * 60),
            planName: "Upper Body",
            entries: [
                entry(.shoulderPress, name: "Shoulder Press", reps: [10, 9]),
                entry(.hammerCurl, name: "Hammer Curl", reps: [10, 10]),
                entry(.dumbbellRow, name: "Dumbbell Row", reps: [9, 9, 9, 8], sides: ["L", "R", "L", "R"])
            ]
        )

        let stats = WeeklyStats(records: [workout], now: FixedClock.date, calendar: calendar)

        XCTAssertEqual(stats.recent.first?.name, "Upper Body")
        XCTAssertEqual(stats.recent.first?.meta, "26 min · 8 sets · 74 reps")
        XCTAssertEqual(stats.recent.first?.day, "Wed")
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func record(start: Date, durationMinutes: Int, name: String) -> WorkoutRecord {
        WorkoutRecord(
            startedAt: start,
            endedAt: start.addingTimeInterval(Double(durationMinutes * 60)),
            planName: name,
            entries: [entry(.shoulderPress, name: "Shoulder Press", reps: [10, 9])]
        )
    }

    private func entry(_ exerciseID: ExerciseID, name: String, reps: [Int], sides: [String]? = nil) -> WorkoutRecordEntry {
        WorkoutRecordEntry(
            exerciseID: exerciseID,
            name: name,
            outcome: .completed,
            sets: reps.enumerated().map { index, count in
                RecordedSet(reps: count, side: sides?.indices.contains(index) == true ? sides?[index] : nil, weight: nil)
            }
        )
    }
}
