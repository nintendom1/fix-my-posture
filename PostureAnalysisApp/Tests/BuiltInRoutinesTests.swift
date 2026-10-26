import Foundation
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class BuiltInRoutinesTests: XCTestCase {
    // Starter routines leave up to one minute for cooldown after completion.
    private let cooldownAllowanceSeconds = 60.0

    /// One row per starter routine, in catalog order. Each issue (#76–#81) adds its row.
    private let expectedRoutines: [(issue: String, name: String, exercises: [ExerciseID], reps: [Int])] = [
        ("76", "Upper Body", [.pushUp, .dumbbellRow, .shoulderPress], [8, 8, 8]),
        ("77", "Chest & Arms", [.pushUp, .hammerCurl, .tricepsExtension], [10, 10, 10]),
        ("78", "Lower Body", [.airSquat, .stiffLegDeadlift, .rearLunge], [10, 8, 5]),
        ("79", "Shoulders & Arms", [.shoulderPress, .lateralRaise, .hammerCurl], [8, 8, 10]),
        ("80", "Back & Posture", [.dumbbellRow, .dumbbellShrug], [10, 15]),
        ("81", "Legs & Glutes", [.airSquat, .stiffLegDeadlift, .gluteBridge], [10, 8, 10])
    ]

    func testStarterRoutinesUseTheirFixedIdentityAndCatalogOrder() {
        XCTAssertEqual(BuiltInRoutines.all.map(\.name), expectedRoutines.map(\.name))
        for (routine, expected) in zip(BuiltInRoutines.all, expectedRoutines) {
            XCTAssertEqual(routine.id, uuid("5E7A0000-0000-4000-8000-0000000000\(expected.issue)"), expected.name)
            XCTAssertEqual(routine.items.map(\.id), expected.exercises.indices.map { index in
                uuid("5E7A00\(expected.issue)-0000-4000-8000-00000000000\(index + 1)")
            }, expected.name)
            XCTAssertEqual(routine.items.map(\.exerciseID), expected.exercises, expected.name)
            XCTAssertEqual(routine.items.map(\.targetReps), expected.reps.map { $0...$0 }, expected.name)
        }
    }

    func testEveryBuiltInHasUniqueIdsValidExercisesAndMeetsTheStarterCap() {
        let allIDs = BuiltInRoutines.all.flatMap { [$0.id] + $0.items.map(\.id) }
        XCTAssertEqual(Set(allIDs).count, allIDs.count, "Routine and item ids must all be unique.")

        for routine in BuiltInRoutines.all {
            XCTAssertTrue((1...3).contains(routine.items.count), routine.name)
            XCTAssertTrue(routine.items.allSatisfy { $0.setCount == 1 }, routine.name)
            XCTAssertTrue(routine.items.allSatisfy { item in
                ExerciseCatalog.all.contains { $0.id == item.exerciseID }
            }, routine.name)
            XCTAssertLessThan(
                RoutineEstimator.seconds(for: routine, exercises: ExerciseCatalog.all, restPolicy: .exerciseDefault)
                    + cooldownAllowanceSeconds,
                420,
                routine.name
            )
        }
    }

    func testLowerBodyEstimateIs332Seconds() throws {
        let lowerBody = try XCTUnwrap(BuiltInRoutines.all.first { $0.name == "Lower Body" })
        XCTAssertEqual(RoutineEstimator.seconds(for: lowerBody, exercises: ExerciseCatalog.all,
                                                  restPolicy: .exerciseDefault), 332)
    }

    func testShouldersAndArmsEstimateIs344Seconds() throws {
        let routine = try XCTUnwrap(BuiltInRoutines.all.first { $0.name == "Shoulders & Arms" })
        XCTAssertEqual(RoutineEstimator.seconds(for: routine, exercises: ExerciseCatalog.all,
                                                  restPolicy: .exerciseDefault), 344)
    }

    func testBackAndPostureHasTwoExercisesAndIs285Seconds() throws {
        let routine = try XCTUnwrap(BuiltInRoutines.all.first { $0.name == "Back & Posture" })
        XCTAssertEqual(routine.items.count, 2, "Back & Posture intentionally has two exercises.")
        XCTAssertEqual(RoutineEstimator.seconds(for: routine, exercises: ExerciseCatalog.all,
                                                  restPolicy: .exerciseDefault), 285)
    }

    func testLegsAndGlutesEstimateIs322Seconds() throws {
        let routine = try XCTUnwrap(BuiltInRoutines.all.first { $0.name == "Legs & Glutes" })
        XCTAssertEqual(RoutineEstimator.seconds(for: routine, exercises: ExerciseCatalog.all,
                                                  restPolicy: .exerciseDefault), 322)
    }

    private func uuid(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else {
            XCTFail("Invalid UUID literal: \(value)")
            return UUID()
        }
        return id
    }
}
