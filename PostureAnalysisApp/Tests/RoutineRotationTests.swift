import Foundation
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class RoutineRotationTests: XCTestCase {
    func testNeverDoneRoutinesComeFirstInOldestCreationOrder() throws {
        let early = record(name: "Early", createdAt: date(10))
        let later = record(name: "Later", createdAt: date(20))
        let done = record(name: "Done", createdAt: date(1))
        let history = [workout(for: done.set.id, name: done.set.name, endedAt: date(100))]

        XCTAssertEqual(
            RoutineRotation.upNext(routines: [later, done, early], records: history, override: nil)?.id,
            early.set.id
        )
    }

    func testLeastRecentlyDoneRoutineComesNextWhenAllHaveBeenDone() throws {
        let first = record(name: "First", createdAt: date(10))
        let second = record(name: "Second", createdAt: date(20))
        let history = [
            workout(for: first.set.id, name: first.set.name, endedAt: date(200)),
            workout(for: second.set.id, name: second.set.name, endedAt: date(100))
        ]

        XCTAssertEqual(
            RoutineRotation.upNext(routines: [first, second], records: history, override: nil)?.id,
            second.set.id
        )
    }

    func testPlanIDMatchesRoutineEvenWhenSavedPlanNameDiffers() {
        let routine = record(name: "Current name", createdAt: date(10))
        let history = [workout(for: routine.set.id, name: "Old saved name", endedAt: date(100))]

        XCTAssertEqual(RoutineRotation.lastDone(routine: routine.set, records: history), date(100))
    }

    func testLegacyRecordWithoutPlanIDFallsBackToPlanName() {
        let routine = record(name: "Legacy routine", createdAt: date(10))
        let history = [workout(for: nil, name: routine.set.name, endedAt: date(100))]

        XCTAssertEqual(RoutineRotation.lastDone(routine: routine.set, records: history), date(100))
    }

    func testOverrideWinsWhenRoutineExists() {
        let first = record(name: "First", createdAt: date(10))
        let second = record(name: "Second", createdAt: date(20))

        XCTAssertEqual(
            RoutineRotation.upNext(routines: [first, second], records: [], override: second.set.id)?.id,
            second.set.id
        )
    }

    func testOverrideForDeletedRoutineIsIgnored() {
        let existing = record(name: "Existing", createdAt: date(20))
        let deletedID = UUID()

        XCTAssertEqual(
            RoutineRotation.upNext(routines: [existing], records: [], override: deletedID)?.id,
            existing.set.id
        )
    }

    func testSavingFinishedRoutineWorkoutClearsUpNextOverride() throws {
        let preferences = InMemoryPreferences()
        preferences.upNextOverride = UUID()
        let repository = HistorySaveTestRepository()
        let workout = workout(for: UUID(), name: "Saved routine", endedAt: date(100))

        try WorkoutHistorySaver.save(workout, using: repository, preferences: preferences)

        XCTAssertEqual(repository.savedRecords, [workout])
        XCTAssertNil(preferences.upNextOverride)
    }

    func testSavingExerciseWorkoutDoesNotClearUpNextOverride() throws {
        let preferences = InMemoryPreferences()
        let override = UUID()
        preferences.upNextOverride = override
        let repository = HistorySaveTestRepository()
        let workout = workout(for: nil, name: "Exercise", endedAt: date(100))

        try WorkoutHistorySaver.save(workout, using: repository, preferences: preferences)

        XCTAssertEqual(preferences.upNextOverride, override)
    }

    private func record(name: String, createdAt: Date) -> SavedExerciseSetRecord {
        SavedExerciseSetRecord(
            set: SavedExerciseSet(name: name, items: []),
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    private func workout(for id: UUID?, name: String, endedAt: Date) -> WorkoutRecord {
        WorkoutRecord(
            startedAt: endedAt.addingTimeInterval(-60),
            endedAt: endedAt,
            planID: id,
            planName: name,
            entries: [WorkoutRecordEntry(
                exerciseID: .shoulderPress,
                name: "Shoulder Press",
                outcome: .completed,
                sets: [RecordedSet(reps: 1)]
            )]
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}

@MainActor
private final class HistorySaveTestRepository: WorkoutHistoryRepository {
    private(set) var savedRecords: [WorkoutRecord] = []

    func list() throws -> [WorkoutRecord] { savedRecords }
    func save(_ record: WorkoutRecord) throws { savedRecords.append(record) }
    func updateWeights(for record: WorkoutRecord) throws {}
    func delete(id: UUID) throws {}
}
