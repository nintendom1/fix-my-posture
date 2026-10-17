import XCTest
@testable import PostureAnalysisApp

final class SavedExerciseSetTests: XCTestCase {
    private let press = ShoulderPressExercise.definition()
    private let curl = HammerCurlExercise.definition()

    func testItemsKeepOrderAndRepeatsThroughStorage() throws {
        let set = SavedExerciseSet(name: "Upper Body", items: [
            SavedExerciseSetItem(exerciseID: press.id, setCount: 2, targetRepMinimum: 8, targetRepMaximum: 10),
            SavedExerciseSetItem(exerciseID: curl.id, setCount: 2, targetRepMinimum: 10, targetRepMaximum: 10),
            SavedExerciseSetItem(exerciseID: press.id, setCount: 1, targetRepMinimum: 12, targetRepMaximum: 12)
        ])
        XCTAssertEqual(SavedExerciseSetEntity(set).value, set, "Order, ids, and repeats survive storage.")

        let plan = set.plan(in: [press, curl])
        XCTAssertEqual(plan.items.map(\.exerciseID), [press.id, curl.id, press.id])
        XCTAssertEqual(plan.items.map(\.id), set.items.map(\.id), "Each occurrence keeps its own id.")
        XCTAssertEqual(plan.items[2].targetReps, 12...12)
    }

    func testUnavailableExercisesNeedAttentionInsteadOfBreakingTheSet() {
        let set = SavedExerciseSet(name: "Old", items: [
            SavedExerciseSetItem(exerciseID: ExerciseID(rawValue: "retired_exercise"), setCount: 2, targetRepMinimum: 5, targetRepMaximum: 5),
            SavedExerciseSetItem(exerciseID: curl.id, setCount: 1, targetRepMinimum: 10, targetRepMaximum: 10)
        ])
        XCTAssertEqual(set.missingItems(in: [press, curl]).count, 1)
        XCTAssertEqual(set.plan(in: [press, curl]).items.map(\.exerciseID), [curl.id], "Only available exercises run.")
        XCTAssertEqual(set.items.count, 2, "Nothing is silently removed.")
    }

    func testDuplicateGetsFreshIdsAndCopyName() {
        let set = SavedExerciseSet(name: "Legs", items: [SavedExerciseSetItem(exercise: press)])
        let copy = set.duplicated()
        XCTAssertEqual(copy.name, "Legs Copy")
        XCTAssertNotEqual(copy.id, set.id)
        XCTAssertNotEqual(copy.items.first?.id, set.items.first?.id)
        XCTAssertEqual(copy.items.first?.setCount, set.items.first?.setCount)
    }

    func testRememberedTargetsApplyWithoutChangingDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SavedExerciseSetTests"))
        defaults.removePersistentDomain(forName: "SavedExerciseSetTests")
        let preferences = UserDefaultsPreferences(defaults: defaults)
        ExerciseTargetStore.setTarget(ExerciseTarget(sets: 3, repMinimum: 12, repMaximum: 15),
                                      for: press.id, preferences: preferences)
        let applied = ExerciseTargetStore.applying(to: [press, curl], preferences: preferences)
        XCTAssertEqual(applied[0].sets, 3)
        XCTAssertEqual(applied[0].autoCompleteReps, 15)
        XCTAssertEqual(applied[0].targetRangeAnnouncementReps, 12)
        XCTAssertEqual(applied[1].sets, curl.sets, "Other exercises keep their defaults.")
        XCTAssertEqual(press.sets, 2, "The built-in definition never changes.")

        ExerciseTargetStore.setTarget(nil, for: press.id, preferences: preferences)
        XCTAssertEqual(ExerciseTargetStore.applying(to: [press], preferences: preferences)[0].sets, 2,
                       "Reset restores the default.")
    }
}
