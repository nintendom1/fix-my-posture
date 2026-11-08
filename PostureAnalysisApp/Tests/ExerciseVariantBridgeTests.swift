import AdaptiveTraining
import XCTest
@testable import PostureAnalysisApp

final class ExerciseVariantBridgeTests: XCTestCase {
    private let bridge = ExerciseVariantBridge()
    private var rungs: [ProgressionRung] { bridge.ladders.families.flatMap(\.rungs) }

    func testEveryLadderExerciseIsBuiltOrListedAsNotYetBuilt() {
        let built = Set(ExerciseCatalog.all.map(\.id.rawValue))
        for rung in rungs {
            XCTAssertTrue(built.contains(rung.exerciseID) || ExerciseVariantBridge.notYetBuilt.contains(rung.exerciseID),
                          "\(rung.id) names \(rung.exerciseID), which is neither in the catalog nor listed as not yet built")
        }
    }

    func testNotYetBuiltListsOnlyMissingLadderExercises() {
        let built = Set(ExerciseCatalog.all.map(\.id.rawValue))
        let ladderIDs = Set(rungs.map(\.exerciseID))
        for id in ExerciseVariantBridge.notYetBuilt {
            XCTAssertFalse(built.contains(id), "\(id) is in the catalog now; remove it from notYetBuilt")
            XCTAssertTrue(ladderIDs.contains(id), "\(id) is not used by any ladder")
        }
    }

    func testBuiltRungsNeedTheSameEquipmentAsTheirExercise() {
        for rung in rungs {
            guard let exercise = bridge.exercise(for: rung) else { continue }
            XCTAssertEqual(rung.requiredEquipment, ExerciseVariantBridge.trainingEquipment(for: exercise.equipment),
                           "\(rung.id)")
        }
    }

    func testBuiltRungsCountRepsLikeTheirExercise() {
        // Every exercise in the catalog today counts reps; a timed rung needs a timed exercise.
        for rung in rungs where bridge.exercise(for: rung) != nil {
            XCTAssertEqual(rung.doseRange.kind, .reps, "\(rung.id)")
        }
    }

    func testEveryBuiltRungResolvesAndShallowWallPushUpUsesItsReducedRange() throws {
        for rung in rungs where !ExerciseVariantBridge.notYetBuilt.contains(rung.exerciseID) {
            XCTAssertNotNil(bridge.exercise(for: rung), "\(rung.id) must resolve to a runnable definition")
        }

        let shallowRung = try XCTUnwrap(bridge.ladders.rung(VariantID(rawValue: "push.wall_push_up.shallow")))
        let shallow = try XCTUnwrap(bridge.exercise(for: shallowRung))
        XCTAssertEqual(shallow.id, .wallPushUp)
        XCTAssertEqual(shallow.displayName, "Shallow Wall Push-Up")
        XCTAssertEqual(shallow.spokenName, "shallow wall push-up")
        let baseRung = try XCTUnwrap(bridge.ladders.rung(VariantID(rawValue: "push.wall_push_up")))
        XCTAssertEqual(bridge.exercise(for: baseRung)?.displayName, "Wall Push-Up")
    }

    func testInclinePushUpRungResolvesAndIsNoLongerListedAsMissing() throws {
        XCTAssertFalse(ExerciseVariantBridge.notYetBuilt.contains("incline_push_up"))
        let rung = try XCTUnwrap(bridge.ladders.rung(VariantID(rawValue: "push.incline_push_up")))
        XCTAssertEqual(rung.exerciseID, "incline_push_up")
        let exercise = try XCTUnwrap(bridge.exercise(for: rung))
        XCTAssertEqual(exercise.id, .inclinePushUp)
        XCTAssertEqual(exercise.displayName, "Incline Push-Up")
        XCTAssertNil(exercise.reducedRange, "The incline push-up has no reduced-range variant.")
    }

    func testAvailabilityOffersBuiltExercisesWithinTheUsersEquipment() throws {
        let withoutDumbbells = bridge.availability(equipment: [])
        let pushUp = try XCTUnwrap(bridge.ladders.rung(VariantID(rawValue: "push.push_up")))
        let row = try XCTUnwrap(bridge.ladders.rung(VariantID(rawValue: "row.dumbbell_row")))
        XCTAssertTrue(withoutDumbbells.isAvailable(pushUp))
        XCTAssertFalse(withoutDumbbells.isAvailable(row))
        XCTAssertTrue(bridge.availability(equipment: [.dumbbells]).isAvailable(row))
    }
}
