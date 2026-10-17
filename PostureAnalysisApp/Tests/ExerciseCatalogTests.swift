import UIKit
import XCTest
@testable import PostureAnalysisApp

final class ExerciseCatalogTests: XCTestCase {
    func testEveryCatalogExerciseHasCorePresentationData() {
        XCTAssertFalse(ExerciseCatalog.all.isEmpty)

        for exercise in ExerciseCatalog.all {
            let presentation = exercise.presentation
            XCTAssertFalse(presentation.shortName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           "Missing short name for \(exercise.id.rawValue)")
            XCTAssertFalse(presentation.muscles.isEmpty, "Missing muscles for \(exercise.id.rawValue)")
            XCTAssertTrue(presentation.muscles.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                          "Empty muscle label for \(exercise.id.rawValue)")
            XCTAssertFalse(presentation.filterGroups.isEmpty, "Missing filter groups for \(exercise.id.rawValue)")
        }
    }

    func testEveryPresentationSymbolResolves() {
        for exercise in ExerciseCatalog.all {
            XCTAssertNotNil(UIImage(systemName: exercise.presentation.symbolName),
                            "Unknown SF Symbol \(exercise.presentation.symbolName) for \(exercise.id.rawValue)")
        }
    }

    func testGradientTokensAreUniqueAndHaveValidStops() {
        let presentations = ExerciseCatalog.all.map(\.presentation)
        let tokens = presentations.map(\.gradient.token)
        XCTAssertEqual(Set(tokens).count, tokens.count, "Each exercise needs its own gradient token")

        for (exercise, presentation) in zip(ExerciseCatalog.all, presentations) {
            XCTAssertGreaterThanOrEqual(presentation.gradient.stops.count, 2,
                                        "Gradient needs at least two stops for \(exercise.id.rawValue)")
            for stop in presentation.gradient.stops {
                let hex = stop.hasPrefix("#") ? String(stop.dropFirst()) : stop
                XCTAssertTrue(hex.count == 6 && hex.allSatisfy(\.isHexDigit),
                              "Invalid gradient stop \(stop) for \(exercise.id.rawValue)")
            }
        }
    }

    func testWatchItemsOnlyReferenceThatExercisesCorrectiveCuesAndUseApprovedCopy() {
        let bannedPhrases = ["injury", "pain", "medical", "diagnos", "scoliosis", "posture correction", "cure", "treat"]

        for exercise in ExerciseCatalog.all {
            let correctiveCueIDs = Set(exercise.coachingCues.filter { $0.kind == .corrective }.map(\.id))
            for item in exercise.presentation.watchesFor {
                XCTAssertTrue(correctiveCueIDs.contains(item.cueID),
                              "\(item.cueID.rawValue) is not a corrective cue for \(exercise.id.rawValue)")
                XCTAssertFalse(item.text.hasSuffix("."), "Watch text should not end with a period: \(item.text)")
                XCTAssertLessThanOrEqual(item.text.count, 40, "Watch text is too long: \(item.text)")
                let lowered = item.text.lowercased()
                for bannedPhrase in bannedPhrases {
                    XCTAssertFalse(lowered.contains(bannedPhrase),
                                   "Banned wording '\(bannedPhrase)' in \(item.text)")
                }
            }
        }
    }

    func testFilterGroupsAgreeWithEquipmentAndEveryExerciseHasBodyRegion() {
        for exercise in ExerciseCatalog.all {
            let groups = exercise.presentation.filterGroups
            XCTAssertTrue(groups.contains(.upper) != groups.contains(.lower),
                          "Exercise needs exactly one upper/lower group: \(exercise.id.rawValue)")
            XCTAssertEqual(groups.contains(.dumbbells), exercise.equipment == .dumbbells,
                           "Dumbbell filter does not match equipment for \(exercise.id.rawValue)")
            XCTAssertEqual(groups.contains(.bodyweight), exercise.equipment == .bodyweight,
                           "Bodyweight filter does not match equipment for \(exercise.id.rawValue)")
            XCTAssertEqual(groups.contains(.band), exercise.equipment == .band,
                           "Band filter does not match equipment for \(exercise.id.rawValue)")
        }
    }

    func testLiveCatalogProviderReturnsCatalogInOrderAndLooksUpByID() {
        let provider = LiveExerciseCatalog()
        XCTAssertEqual(provider.all.map(\.id), ExerciseCatalog.all.map(\.id))

        for exercise in ExerciseCatalog.all {
            XCTAssertEqual(provider.exercise(exercise.id)?.id, exercise.id)
        }
        XCTAssertNil(provider.exercise(ExerciseID(rawValue: "not_an_exercise")))
    }
}
