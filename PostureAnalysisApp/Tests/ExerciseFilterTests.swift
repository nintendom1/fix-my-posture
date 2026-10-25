import Foundation
import XCTest
@testable import PostureAnalysisApp

final class ExerciseFilterTests: XCTestCase {
    private let exercises = ExerciseCatalog.all

    func testEachChipMatchesItsCatalogFilterGroups() {
        let expected: [(ExerciseFilterChip, [ExerciseID])] = [
            (.all, [.shoulderPress, .hammerCurl, .tricepsExtension, .airSquat, .stiffLegDeadlift, .rearLunge, .dumbbellRow, .pushUp]),
            (.upper, [.shoulderPress, .hammerCurl, .tricepsExtension, .dumbbellRow, .pushUp]),
            (.lower, [.airSquat, .stiffLegDeadlift, .rearLunge]),
            (.bodyweight, [.airSquat, .pushUp]),
            (.dumbbells, [.shoulderPress, .hammerCurl, .stiffLegDeadlift, .rearLunge, .dumbbellRow])
        ]

        for (chip, exerciseIDs) in expected {
            XCTAssertEqual(ids(for: chip), exerciseIDs, "Unexpected membership for \(chip.title)")
        }
    }

    func testQueryMatchesDisplayAndShortNames() {
        XCTAssertEqual(ids(matching: "one-arm"), [.dumbbellRow])
        XCTAssertEqual(ids(matching: "press"), [.shoulderPress])
    }

    func testQueryMatchesMusclesAndEquipment() {
        XCTAssertEqual(ids(matching: "triceps"), [.shoulderPress, .tricepsExtension, .pushUp])
        XCTAssertEqual(ids(matching: "band"), [.tricepsExtension])
    }

    func testQueryMatchingIgnoresCaseAndDiacritics() {
        XCTAssertEqual(ids(matching: "TRICEPS"), [.shoulderPress, .tricepsExtension, .pushUp])
        XCTAssertEqual(ids(matching: "Dumbbéll"), [.shoulderPress, .hammerCurl, .stiffLegDeadlift, .rearLunge, .dumbbellRow])
    }

    func testEveryWhitespaceSeparatedQueryTokenMustMatch() {
        XCTAssertEqual(ids(matching: "back dumbbell"), [.dumbbellRow])
        XCTAssertTrue(ids(matching: "back squat").isEmpty)
    }

    func testEmptyQueryReturnsEverythingInCatalogOrder() {
        XCTAssertEqual(ExerciseFilter.apply(exercises, chip: .all, query: " \n\t ").map(\.id), exercises.map(\.id))
    }

    func testChipFilteringPreservesCatalogOrder() {
        XCTAssertEqual(ids(for: .dumbbells), [.shoulderPress, .hammerCurl, .stiffLegDeadlift, .rearLunge, .dumbbellRow])
    }

    func testNoMatchesReturnsAnEmptyList() {
        XCTAssertTrue(ExerciseFilter.apply(exercises, chip: .all, query: "unlisted movement").isEmpty)
    }

    private func ids(for chip: ExerciseFilterChip) -> [ExerciseID] {
        ExerciseFilter.apply(exercises, chip: chip, query: "").map(\.id)
    }

    private func ids(matching query: String) -> [ExerciseID] {
        ExerciseFilter.apply(exercises, chip: .all, query: query).map(\.id)
    }
}
