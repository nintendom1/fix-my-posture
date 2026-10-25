import Foundation
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class BuiltInRoutinesTests: XCTestCase {
    // Starter routines leave up to one minute for cooldown after completion.
    private let cooldownAllowanceSeconds = 60.0

    func testUpperBodyUsesItsFixedIdentityAndCatalogOrder() throws {
        let upperBody = try XCTUnwrap(BuiltInRoutines.all.first)
        XCTAssertEqual(BuiltInRoutines.all.count, 1)
        XCTAssertEqual(upperBody.id, uuid("5E7A0000-0000-4000-8000-000000000076"))
        XCTAssertEqual(upperBody.name, "Upper Body")
        XCTAssertEqual(upperBody.items.map(\.id), [
            uuid("5E7A0076-0000-4000-8000-000000000001"),
            uuid("5E7A0076-0000-4000-8000-000000000002"),
            uuid("5E7A0076-0000-4000-8000-000000000003")
        ])
        XCTAssertEqual(upperBody.items.map(\.exerciseID), [.pushUp, .dumbbellRow, .shoulderPress])
        XCTAssertEqual(upperBody.items.map(\.targetReps), [8...8, 8...8, 8...8])
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

    private func uuid(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else {
            XCTFail("Invalid UUID literal: \(value)")
            return UUID()
        }
        return id
    }
}
