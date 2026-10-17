import XCTest
@testable import PostureAnalysisApp

final class WorkoutCompletionStatsTests: XCTestCase {
    func testPlanRecordTotalsAndRows() {
        let stats = WorkoutCompletionStats(record: planRecord())

        XCTAssertEqual(stats.exerciseCount, 4)
        XCTAssertEqual(stats.totalSets, 10)
        XCTAssertEqual(stats.totalReps, 94)
        XCTAssertEqual(stats.durationLabel, "26m")
        XCTAssertEqual(stats.exerciseRows.map(\.summary), [
            "Shoulder Press — 2 sets · 19 reps · 20 lb",
            "Hammer Curl — 2 sets · 20 reps · 17.5 lb",
            "Dumbbell Row — 4 sets · 32 reps · 20 lb / side",
            "Air Squat — 2 sets · 23 reps"
        ])
    }

    func testSingleExerciseRecordTotals() {
        let record = WorkoutRecord(
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 400),
            planName: nil,
            entries: [entry(.shoulderPress, "Shoulder Press", reps: [8, 9])]
        )

        let stats = WorkoutCompletionStats(record: record)

        XCTAssertEqual(stats.exerciseCount, 1)
        XCTAssertEqual(stats.totalSets, 2)
        XCTAssertEqual(stats.totalReps, 17)
        XCTAssertEqual(stats.durationLabel, "5m")
        XCTAssertEqual(stats.exerciseRows.first?.summary, "Shoulder Press — 2 sets · 17 reps")
    }

    func testDurationRoundsToNearestMinuteAndShowsUnderOneMinute() {
        XCTAssertEqual(WorkoutCompletionStats(record: record(duration: 60 * 25 + 29)).durationLabel, "25m")
        XCTAssertEqual(WorkoutCompletionStats(record: record(duration: 60 * 25 + 30)).durationLabel, "26m")
        XCTAssertEqual(WorkoutCompletionStats(record: record(duration: 59)).durationLabel, "<1m")
    }

    func testSkippedExerciseCountsButAddsNoSetsOrReps() {
        let skipped = WorkoutRecordEntry(exerciseID: .hammerCurl, name: "Hammer Curl", outcome: .skipped, sets: [])
        let workout = WorkoutRecord(
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 60),
            planName: "Upper Body",
            entries: [entry(.shoulderPress, "Shoulder Press", reps: [10, 9]), skipped]
        )

        let stats = WorkoutCompletionStats(record: workout)

        XCTAssertEqual(stats.exerciseCount, 2)
        XCTAssertEqual(stats.totalSets, 2)
        XCTAssertEqual(stats.totalReps, 19)
        XCTAssertEqual(stats.exerciseRows[1].summary, "Hammer Curl — Skipped")
    }

    func testOneArmWeightIsMarkedPerSide() {
        let row = WorkoutCompletionStats(record: planRecord()).exerciseRows[2]

        XCTAssertEqual(row.weightLabel, "20 lb / side")
        XCTAssertTrue(row.summary.contains("20 lb / side"))
    }

    func testLatestWeightIncludesItsUnit() {
        let weighted = WorkoutRecordEntry(
            exerciseID: .shoulderPress,
            name: "Shoulder Press",
            outcome: nil,
            sets: [
                RecordedSet(reps: 8, side: nil, weight: .mass(15, .pounds)),
                RecordedSet(reps: 9, side: nil, weight: .mass(8, .kilograms))
            ]
        )
        let workout = WorkoutRecord(
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 120),
            planName: nil,
            entries: [weighted]
        )

        XCTAssertEqual(WorkoutCompletionStats(record: workout).exerciseRows[0].weightLabel, "8 kg")
    }

    func testEmptyRecordProducesZeroMetricsAndNoRows() {
        let workout = WorkoutRecord(
            startedAt: Date(timeIntervalSince1970: 10),
            endedAt: Date(timeIntervalSince1970: 10),
            planName: nil,
            entries: []
        )

        let stats = WorkoutCompletionStats(record: workout)

        XCTAssertEqual(stats.exerciseCount, 0)
        XCTAssertEqual(stats.totalSets, 0)
        XCTAssertEqual(stats.totalReps, 0)
        XCTAssertEqual(stats.durationLabel, "<1m")
        XCTAssertTrue(stats.exerciseRows.isEmpty)
    }

    private func planRecord() -> WorkoutRecord {
        WorkoutRecord(
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 100 + 26 * 60),
            planName: "Upper Body",
            entries: [
                entry(.shoulderPress, "Shoulder Press", reps: [10, 9], weights: [.mass(20, .pounds), .mass(20, .pounds)]),
                entry(.hammerCurl, "Hammer Curl", reps: [10, 10], weights: [.mass(15, .pounds), .mass(17.5, .pounds)]),
                entry(.dumbbellRow, "Dumbbell Row", reps: [8, 8, 8, 8], sides: ["L", "R", "L", "R"],
                      weights: [.mass(20, .pounds), .mass(20, .pounds), .mass(20, .pounds), .mass(20, .pounds)]),
                entry(.airSquat, "Air Squat", reps: [12, 11])
            ]
        )
    }

    private func record(duration: TimeInterval) -> WorkoutRecord {
        WorkoutRecord(
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: duration),
            planName: nil,
            entries: [entry(.shoulderPress, "Shoulder Press", reps: [1])]
        )
    }

    private func entry(
        _ id: ExerciseID,
        _ name: String,
        reps: [Int],
        sides: [String]? = nil,
        weights: [WorkoutWeight?] = []
    ) -> WorkoutRecordEntry {
        WorkoutRecordEntry(
            exerciseID: id,
            name: name,
            outcome: nil,
            sets: reps.enumerated().map { index, count in
                RecordedSet(reps: count,
                            side: sides?.indices.contains(index) == true ? sides?[index] : nil,
                            weight: weights.indices.contains(index) ? weights[index] : nil)
            }
        )
    }
}
