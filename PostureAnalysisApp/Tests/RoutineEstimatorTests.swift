import Foundation
import XCTest
@testable import PostureAnalysisApp

final class RoutineEstimatorTests: XCTestCase {
    private let exercises = ExerciseCatalog.all

    func testDesignRoutineEstimatesAreWithinTwoMinutes() {
        let upperBody = routine("Upper Body", [(.shoulderPress, 2, 8, 10), (.dumbbellRow, 2, 8, 10),
                                                 (.hammerCurl, 2, 10, 10), (.tricepsExtension, 2, 10, 10)])
        let quickStrength = routine("Quick Strength", [(.airSquat, 2, 15, 15), (.pushUp, 2, 10, 10),
                                                          (.shoulderPress, 2, 8, 10)])
        let legsAndPush = routine("Legs & Push", [(.airSquat, 3, 15, 15), (.pushUp, 3, 10, 10)])

        assertEstimate(RoutineEstimator.minutes(for: upperBody, exercises: exercises, restPolicy: .exerciseDefault), near: 25)
        assertEstimate(RoutineEstimator.minutes(for: quickStrength, exercises: exercises, restPolicy: .exerciseDefault), near: 16)
        assertEstimate(RoutineEstimator.minutes(for: legsAndPush, exercises: exercises, restPolicy: .exerciseDefault), near: 15)
    }

    func testTenSetEditorExampleIsWithinTwoMinutesOfThirty() {
        let upperBody = routine("Upper Body", [(.shoulderPress, 3, 8, 10), (.dumbbellRow, 3, 8, 10),
                                                 (.hammerCurl, 2, 10, 10), (.tricepsExtension, 2, 10, 10)])

        assertEstimate(RoutineEstimator.minutes(for: upperBody, exercises: exercises, restPolicy: .exerciseDefault), near: 30)
    }

    func testFixedRestPolicyChangesTheEstimate() {
        let upperBody = routine("Upper Body", [(.shoulderPress, 2, 8, 10), (.dumbbellRow, 2, 8, 10),
                                                 (.hammerCurl, 2, 10, 10), (.tricepsExtension, 2, 10, 10)])
        let defaults = RoutineEstimator.minutes(for: upperBody, exercises: exercises, restPolicy: .exerciseDefault)
        let fixed = RoutineEstimator.minutes(for: upperBody, exercises: exercises, restPolicy: .fixed(seconds: 45))

        XCTAssertNotEqual(defaults, fixed)
    }

    func testPerSideExerciseDoublesItsRepetitionTime() {
        let row = ExerciseCatalog.definition(for: .dumbbellRow)!
        var oneSided = row
        oneSided.perSide = false
        let routine = SavedExerciseSet(name: "Row", items: [
            SavedExerciseSetItem(exerciseID: .dumbbellRow, setCount: 2, targetRepMinimum: 8, targetRepMaximum: 10)
        ])

        let bothSides = RoutineEstimator.minutes(for: routine, exercises: [row], restPolicy: .exerciseDefault)
        let oneSide = RoutineEstimator.minutes(for: routine, exercises: [oneSided], restPolicy: .exerciseDefault)

        XCTAssertGreaterThan(bothSides, oneSide)
    }

    func testEmptyRoutineHasZeroMinutes() {
        XCTAssertEqual(
            RoutineEstimator.minutes(for: SavedExerciseSet(name: "Empty", items: []),
                                     exercises: exercises, restPolicy: .exerciseDefault),
            0
        )
    }

    private func assertEstimate(_ actual: Int, near expected: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(abs(actual - expected), 2, "Expected about \(expected) min, got \(actual) min", file: file, line: line)
    }

    private func routine(_ name: String, _ items: [(ExerciseID, Int, Int, Int)]) -> SavedExerciseSet {
        SavedExerciseSet(name: name, items: items.map { id, sets, minimum, maximum in
            SavedExerciseSetItem(exerciseID: id, setCount: sets, targetRepMinimum: minimum, targetRepMaximum: maximum)
        })
    }
}
