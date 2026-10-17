import Foundation
import XCTest
@testable import PostureAnalysisApp

final class PreferencesStoreTests: XCTestCase {
    func testLegacyValuesAreReadWithoutChangingTheirKeysOrFormats() throws {
        let suiteName = "PreferencesStoreTests.Legacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let target = ExerciseTarget(sets: 3, repMinimum: 8, repMaximum: 12)
        defaults.set(false, forKey: "cameraTiltCompensationEnabled")
        defaults.set(false, forKey: "showHorizonLine")
        defaults.set(9, forKey: "feedbackRefreshRate")
        defaults.set(true, forKey: "workoutCoach.showMeasurements")
        defaults.set(true, forKey: "workoutCoach.coachMuted")
        defaults.set(false, forKey: "workoutCoach.micMuted")
        defaults.set(true, forKey: "workoutCoach.voiceTipSpoken")
        defaults.set(true, forKey: "workoutCoach.guideSeen.shoulder_press")
        defaults.set(try JSONEncoder().encode(target), forKey: "workoutCoach.target.shoulder_press")

        let preferences = UserDefaultsPreferences(defaults: defaults)

        XCTAssertFalse(preferences.cameraTiltCompensationEnabled)
        XCTAssertFalse(preferences.showHorizonLine)
        XCTAssertEqual(preferences.feedbackRefreshRate, 9)
        XCTAssertTrue(preferences.workoutCoachShowMeasurements)
        XCTAssertTrue(preferences.workoutCoachCoachMuted)
        XCTAssertFalse(preferences.workoutCoachMicMuted)
        XCTAssertTrue(preferences.workoutCoachVoiceTipSpoken)
        XCTAssertTrue(preferences.guideSeen(for: "shoulder_press"))
        XCTAssertEqual(preferences.exerciseTarget(for: "shoulder_press"), target)
    }

    func testWritesKeepTheLegacyOnDiskFormat() throws {
        let suiteName = "PreferencesStoreTests.WriteLegacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserDefaultsPreferences(defaults: defaults)
        let target = ExerciseTarget(sets: 4, repMinimum: 6, repMaximum: 10)

        preferences.cameraTiltCompensationEnabled = false
        preferences.showHorizonLine = false
        preferences.showAlignmentTargets = false
        preferences.feedbackRefreshRate = 7
        preferences.workoutCoachShowMeasurements = true
        preferences.workoutCoachCoachMuted = true
        preferences.workoutCoachMicMuted = true
        preferences.workoutCoachVoiceTipSpoken = true
        preferences.setGuideSeen(true, for: "hammer_curl")
        preferences.setExerciseTarget(target, for: "hammer_curl")

        XCTAssertEqual(defaults.object(forKey: "cameraTiltCompensationEnabled") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "showHorizonLine") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: PreferenceKey.showAlignmentTargets) as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "feedbackRefreshRate") as? Int, 7)
        XCTAssertEqual(defaults.object(forKey: "workoutCoach.showMeasurements") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "workoutCoach.coachMuted") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "workoutCoach.micMuted") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "workoutCoach.voiceTipSpoken") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "workoutCoach.guideSeen.hammer_curl") as? Bool, true)

        let targetData = try XCTUnwrap(defaults.data(forKey: "workoutCoach.target.hammer_curl"))
        let targetJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: targetData) as? [String: Int])
        XCTAssertEqual(targetJSON, ["sets": 4, "repMinimum": 6, "repMaximum": 10])
        XCTAssertEqual(try JSONDecoder().decode(ExerciseTarget.self, from: targetData), target)
    }

    func testDefaultsMatchTheExistingAppDefaults() throws {
        let suiteName = "PreferencesStoreTests.Defaults.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserDefaultsPreferences(defaults: defaults)

        XCTAssertTrue(preferences.cameraTiltCompensationEnabled)
        XCTAssertTrue(preferences.showHorizonLine)
        XCTAssertEqual(preferences.feedbackRefreshRate, 5)
        XCTAssertTrue(preferences.showAlignmentTargets)
        XCTAssertFalse(preferences.workoutCoachShowMeasurements)
        XCTAssertFalse(preferences.workoutCoachCoachMuted)
        XCTAssertFalse(preferences.workoutCoachMicMuted)
        XCTAssertFalse(preferences.workoutCoachVoiceTipSpoken)
        XCTAssertFalse(preferences.guideSeen(for: "shoulder_press"))
        XCTAssertNil(preferences.exerciseTarget(for: "shoulder_press"))

        XCTAssertEqual(preferences.restPolicy, .exerciseDefault)
        XCTAssertEqual(preferences.weightUnit, .lb)
        XCTAssertTrue(preferences.startByHolding)
        XCTAssertNil(preferences.upNextOverride)
    }

    func testAlignmentTargetsPreferenceDefaultsOnAndRoundTrips() throws {
        let suiteName = "PreferencesStoreTests.AlignmentTargets.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserDefaultsPreferences(defaults: defaults)

        XCTAssertTrue(preferences.showAlignmentTargets)
        preferences.showAlignmentTargets = false
        XCTAssertFalse(UserDefaultsPreferences(defaults: defaults).showAlignmentTargets)
        XCTAssertEqual(defaults.object(forKey: PreferenceKey.showAlignmentTargets) as? Bool, false)
    }

    func testRestPolicyClampsAndRoundTrips() throws {
        let suiteName = "PreferencesStoreTests.RestPolicy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserDefaultsPreferences(defaults: defaults)

        preferences.restPolicy = .fixed(seconds: 10)
        XCTAssertEqual(preferences.restPolicy, .fixed(seconds: 30))

        preferences.restPolicy = .fixed(seconds: 130)
        XCTAssertEqual(preferences.restPolicy, .fixed(seconds: 120))

        preferences.restPolicy = .fixed(seconds: 47)
        let reloaded = UserDefaultsPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.restPolicy, .fixed(seconds: 47))
    }

    func testInMemoryAndUserDefaultsPreferencesShareTheSameContract() throws {
        let suiteName = "PreferencesStoreTests.Contract.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        assertSharedContract(UserDefaultsPreferences(defaults: defaults))
        assertSharedContract(InMemoryPreferences())
    }

    private func assertSharedContract(_ preferences: any AppPreferencesStoring) {
        let overrideID = UUID()

        preferences.cameraTiltCompensationEnabled = false
        preferences.showHorizonLine = false
        preferences.showAlignmentTargets = false
        preferences.feedbackRefreshRate = 11
        preferences.workoutCoachShowMeasurements = true
        preferences.workoutCoachCoachMuted = true
        preferences.workoutCoachMicMuted = true
        preferences.workoutCoachVoiceTipSpoken = true
        preferences.setGuideSeen(true, for: "contract_exercise")
        preferences.setExerciseTarget(ExerciseTarget(sets: 2, repMinimum: 9, repMaximum: 13),
                                     for: "contract_exercise")
        preferences.restPolicy = .fixed(seconds: 130)
        preferences.weightUnit = .kg
        preferences.startByHolding = false
        preferences.upNextOverride = overrideID

        XCTAssertFalse(preferences.cameraTiltCompensationEnabled)
        XCTAssertFalse(preferences.showHorizonLine)
        XCTAssertFalse(preferences.showAlignmentTargets)
        XCTAssertEqual(preferences.feedbackRefreshRate, 11)
        XCTAssertTrue(preferences.workoutCoachShowMeasurements)
        XCTAssertTrue(preferences.workoutCoachCoachMuted)
        XCTAssertTrue(preferences.workoutCoachMicMuted)
        XCTAssertTrue(preferences.workoutCoachVoiceTipSpoken)
        XCTAssertTrue(preferences.guideSeen(for: "contract_exercise"))
        XCTAssertEqual(preferences.exerciseTarget(for: "contract_exercise"),
                       ExerciseTarget(sets: 2, repMinimum: 9, repMaximum: 13))
        XCTAssertEqual(preferences.restPolicy, .fixed(seconds: 120))
        XCTAssertEqual(preferences.weightUnit, .kg)
        XCTAssertFalse(preferences.startByHolding)
        XCTAssertEqual(preferences.upNextOverride, overrideID)

        preferences.restPolicy = .fixed(seconds: 60)
        XCTAssertEqual(preferences.restPolicy, .fixed(seconds: 60))

        preferences.setGuideSeen(false, for: "contract_exercise")
        preferences.setExerciseTarget(nil, for: "contract_exercise")
        preferences.upNextOverride = nil
        XCTAssertFalse(preferences.guideSeen(for: "contract_exercise"))
        XCTAssertNil(preferences.exerciseTarget(for: "contract_exercise"))
        XCTAssertNil(preferences.upNextOverride)
    }
}
