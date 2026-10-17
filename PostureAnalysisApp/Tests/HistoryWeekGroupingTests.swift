import XCTest
@testable import PostureAnalysisApp

final class HistoryWeekGroupingTests: XCTestCase {
    private var calendar: Calendar { FixedClock.calendar }

    func testLabelsCurrentPreviousAndOlderWeeks() {
        let records = [
            record(date: date(2026, 10, 14), name: "This week"),
            record(date: date(2026, 10, 7), name: "Last week"),
            record(date: date(2026, 10, 1), name: "Older")
        ]

        let groups = HistoryWeekGrouping(records: records, now: FixedClock.date, calendar: calendar).weeks

        XCTAssertEqual(groups.map(\.title), ["This week", "Last week", "Week of Sep 28"])
    }

    func testRecordsWithinEachWeekAreNewestFirst() {
        let older = record(date: date(2026, 10, 12, hour: 9), name: "Morning")
        let newer = record(date: date(2026, 10, 15, hour: 9), name: "Afternoon")

        let groups = HistoryWeekGrouping(records: [older, newer], now: FixedClock.date, calendar: calendar).weeks

        XCTAssertEqual(groups.first?.records.map(\.planName), ["Afternoon", "Morning"])
    }

    func testSummaryLineCountsWorkoutsAndAddsTheirDurations() {
        let records = [
            record(date: date(2026, 10, 14), name: "Upper Body", durationMinutes: 26),
            record(date: date(2026, 10, 12), name: "Quick Strength", durationMinutes: 18)
        ]

        let group = try! XCTUnwrap(HistoryWeekGrouping(records: records, now: FixedClock.date, calendar: calendar).weeks.first)

        XCTAssertEqual(group.summary, "2 workouts · 44 min")
    }

    func testDesignFixtureMatchesThisWeekAndLastWeekSummaries() {
        let groups = HistoryWeekGrouping(
            records: ProgressHistoryFixtures.records,
            now: FixedClock.date,
            calendar: calendar
        ).weeks

        XCTAssertEqual(groups.map(\.title), ["This week", "Last week"])
        XCTAssertEqual(groups.map(\.summary), ["2 workouts · 44 min", "3 workouts · 50 min"])
        XCTAssertEqual(groups[1].records.map { $0.planName ?? $0.entries.first?.name ?? "" }, ["Legs & Push", "Upper Body", "Shoulder Press"])
    }

    func testYearBoundaryUsesCalendarWeekDatesInsteadOfWeekNumberAlone() {
        let now = date(2027, 1, 5)
        let records = [
            record(date: date(2027, 1, 4), name: "January"),
            record(date: date(2026, 12, 28), name: "December"),
            record(date: date(2026, 12, 21), name: "Older December")
        ]

        let groups = HistoryWeekGrouping(records: records, now: now, calendar: calendar).weeks

        XCTAssertEqual(groups.map(\.title), ["This week", "Last week", "Week of Dec 21"])
        XCTAssertEqual(groups[1].records.first?.planName, "December")
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func record(date: Date, name: String, durationMinutes: Int = 20) -> WorkoutRecord {
        WorkoutRecord(
            startedAt: date,
            endedAt: date.addingTimeInterval(Double(durationMinutes * 60)),
            planName: name,
            entries: [WorkoutRecordEntry(
                exerciseID: .shoulderPress,
                name: "Shoulder Press",
                outcome: .completed,
                sets: [RecordedSet(reps: 10, side: nil, weight: .mass(20, .pounds))]
            )]
        )
    }
}
