import Foundation
import XCTest
@testable import PostureAnalysisApp

final class RoutineEstimatorTests: XCTestCase {
    private let exercises = ExerciseCatalog.all

    func testDesignRoutineEstimatesMatchTheDocumentedFormula() {
        let upperBody = routine("Upper Body", [(.shoulderPress, 2, 8, 10), (.dumbbellRow, 2, 8, 10),
                                                 (.hammerCurl, 2, 10, 10), (.tricepsExtension, 2, 10, 10)])
        let quickStrength = routine("Quick Strength", [(.airSquat, 2, 15, 15), (.pushUp, 2, 10, 10),
                                                          (.shoulderPress, 2, 8, 10)])
        let legsAndPush = routine("Legs & Push", [(.airSquat, 3, 15, 15), (.pushUp, 3, 10, 10)])

        assertEstimate(upperBody, seconds: 981, minutes: 16)
        assertEstimate(quickStrength, seconds: 692, minutes: 12)
        assertEstimate(legsAndPush, seconds: 675, minutes: 11)
    }

    func testTenSetEditorExampleEstimateMatchesTheDocumentedFormula() {
        let upperBody = routine("Upper Body", [(.shoulderPress, 3, 8, 10), (.dumbbellRow, 3, 8, 10),
                                                 (.hammerCurl, 2, 10, 10), (.tricepsExtension, 2, 10, 10)])

        assertEstimate(upperBody, seconds: 1_249, minutes: 21)
    }

    func testBuiltInUpperBodyEstimateMatchesTheDocumentedFormula() throws {
        let upperBody = try XCTUnwrap(BuiltInRoutines.all.first)

        assertEstimate(upperBody, seconds: 348, minutes: 6)
    }

    func testFixedRestPolicyChangesTheEstimate() {
        let upperBody = routine("Upper Body", [(.shoulderPress, 2, 8, 10), (.dumbbellRow, 2, 8, 10),
                                                 (.hammerCurl, 2, 10, 10), (.tricepsExtension, 2, 10, 10)])
        let defaults = RoutineEstimator.seconds(for: upperBody, exercises: exercises, restPolicy: .exerciseDefault)
        let fixed = RoutineEstimator.seconds(for: upperBody, exercises: exercises, restPolicy: .fixed(seconds: 45))

        XCTAssertNotEqual(defaults, fixed)
    }

    func testFixedRestPolicyClampsBelowAndAboveTheWorkoutSettingBounds() throws {
        let press = try XCTUnwrap(ExerciseCatalog.definition(for: .shoulderPress))
        let routine = SavedExerciseSet(name: "Press", items: [
            SavedExerciseSetItem(exerciseID: .shoulderPress, setCount: 2, targetRepMinimum: 8, targetRepMaximum: 8)
        ])

        XCTAssertEqual(
            RoutineEstimator.seconds(for: routine, exercises: [press], restPolicy: .fixed(seconds: 0)),
            154,
            accuracy: 0.001
        )
        XCTAssertEqual(
            RoutineEstimator.seconds(for: routine, exercises: [press], restPolicy: .fixed(seconds: 200)),
            244,
            accuracy: 0.001
        )
    }

    func testPerSideExerciseDoublesItsRepetitionTime() {
        let row = ExerciseCatalog.definition(for: .dumbbellRow)!
        var oneSided = row
        oneSided.perSide = false
        let routine = SavedExerciseSet(name: "Row", items: [
            SavedExerciseSetItem(exerciseID: .dumbbellRow, setCount: 2, targetRepMinimum: 8, targetRepMaximum: 10)
        ])

        let bothSides = RoutineEstimator.seconds(for: routine, exercises: [row], restPolicy: .exerciseDefault)
        let oneSide = RoutineEstimator.seconds(for: routine, exercises: [oneSided], restPolicy: .exerciseDefault)

        XCTAssertGreaterThan(bothSides, oneSide)
    }

    func testEmptyRoutineHasZeroMinutes() {
        XCTAssertEqual(
            RoutineEstimator.seconds(for: SavedExerciseSet(name: "Empty", items: []),
                                     exercises: exercises, restPolicy: .exerciseDefault),
            0,
            accuracy: 0.001
        )
    }

    private func assertEstimate(
        _ routine: SavedExerciseSet,
        seconds expectedSeconds: Double,
        minutes expectedMinutes: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let seconds = RoutineEstimator.seconds(for: routine, exercises: exercises, restPolicy: .exerciseDefault)
        XCTAssertEqual(seconds, expectedSeconds, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(RoutineEstimator.minutes(for: routine, exercises: exercises, restPolicy: .exerciseDefault),
                       expectedMinutes, file: file, line: line)
    }

    private func routine(_ name: String, _ items: [(ExerciseID, Int, Int, Int)]) -> SavedExerciseSet {
        SavedExerciseSet(name: name, items: items.map { id, sets, minimum, maximum in
            SavedExerciseSetItem(exerciseID: id, setCount: sets, targetRepMinimum: minimum, targetRepMaximum: maximum)
        })
    }
}
