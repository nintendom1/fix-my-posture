import Foundation
import XCTest
@testable import PostureAnalysisApp

final class ExerciseFilterTests: XCTestCase {
    private let exercises = ExerciseCatalog.all

    func testEachChipMatchesItsCatalogFilterGroups() {
        let expected: [(ExerciseFilterChip, [ExerciseID])] = [
            (.all, [.shoulderPress, .lateralRaise, .hammerCurl, .tricepsExtension, .airSquat, .stiffLegDeadlift, .rearLunge, .gluteBridge, .dumbbellRow, .dumbbellShrug, .pushUp, .wallPushUp]),
            (.upper, [.shoulderPress, .lateralRaise, .hammerCurl, .tricepsExtension, .dumbbellRow, .dumbbellShrug, .pushUp, .wallPushUp]),
            (.lower, [.airSquat, .stiffLegDeadlift, .rearLunge, .gluteBridge]),
            (.bodyweight, [.airSquat, .gluteBridge, .pushUp, .wallPushUp]),
            (.dumbbells, [.shoulderPress, .lateralRaise, .hammerCurl, .stiffLegDeadlift, .rearLunge, .dumbbellRow, .dumbbellShrug])
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
        XCTAssertEqual(ids(matching: "triceps"), [.shoulderPress, .tricepsExtension, .pushUp, .wallPushUp])
        XCTAssertEqual(ids(matching: "band"), [.tricepsExtension])
    }

    func testQueryMatchingIgnoresCaseAndDiacritics() {
        XCTAssertEqual(ids(matching: "TRICEPS"), [.shoulderPress, .tricepsExtension, .pushUp, .wallPushUp])
        XCTAssertEqual(ids(matching: "Dumbbéll"), [.shoulderPress, .lateralRaise, .hammerCurl, .stiffLegDeadlift, .rearLunge, .dumbbellRow, .dumbbellShrug])
    }

    func testEveryWhitespaceSeparatedQueryTokenMustMatch() {
        XCTAssertEqual(ids(matching: "back dumbbell"), [.dumbbellRow, .dumbbellShrug])
        XCTAssertTrue(ids(matching: "back squat").isEmpty)
    }

    func testEmptyQueryReturnsEverythingInCatalogOrder() {
        XCTAssertEqual(ExerciseFilter.apply(exercises, chip: .all, query: " \n\t ").map(\.id), exercises.map(\.id))
    }

    func testChipFilteringPreservesCatalogOrder() {
        XCTAssertEqual(ids(for: .dumbbells), [.shoulderPress, .lateralRaise, .hammerCurl, .stiffLegDeadlift, .rearLunge, .dumbbellRow, .dumbbellShrug])
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
