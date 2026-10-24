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

    func testWorkoutReminderSchedulePersistsThroughUserDefaults() throws {
        let suiteName = "PreferencesStoreTests.WorkoutReminders.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserDefaultsPreferences(defaults: defaults)
        let startDate = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let settings = WorkoutReminderSettings(
            enabled: true,
            recurrence: .everyOtherDay,
            hour: 19,
            minute: 25,
            everyOtherDayStartDate: startDate,
            weekdays: [2, 5]
        )

        preferences.workoutReminderSettings = settings

        XCTAssertEqual(UserDefaultsPreferences(defaults: defaults).workoutReminderSettings, settings)
        XCTAssertNotNil(defaults.data(forKey: PreferenceKey.workoutReminders))
    }

    func testWorkoutReminderSettingsDecodeLegacyJSONAndRoundTripPlainStyle() throws {
        let legacyJSON = #"{"enabled":true,"recurrence":"daily","hour":18,"minute":30,"everyOtherDayStartDate":0,"weekdays":[2,4,6]}"#
        let legacySettings = try JSONDecoder().decode(
            WorkoutReminderSettings.self,
            from: Data(legacyJSON.utf8)
        )

        XCTAssertTrue(legacySettings.enabled)
        XCTAssertEqual(legacySettings.style, .character)

        var plainSettings = legacySettings
        plainSettings.style = .plain
        let encoded = try JSONEncoder().encode(plainSettings)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutReminderSettings.self, from: encoded), plainSettings)
    }

    func testUserDefaultsReadsLegacyWorkoutReminderSettingsWithoutStyle() throws {
        let suiteName = "PreferencesStoreTests.LegacyWorkoutReminders.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyJSON = #"{"enabled":true,"recurrence":"daily","hour":18,"minute":30,"everyOtherDayStartDate":0,"weekdays":[2,4,6]}"#
        defaults.set(Data(legacyJSON.utf8), forKey: PreferenceKey.workoutReminders)

        let settings = UserDefaultsPreferences(defaults: defaults).workoutReminderSettings

        XCTAssertTrue(settings.enabled)
        XCTAssertEqual(settings.style, .character)
    }

    func testCharacterNotificationIntroDateUsesUnixTimestampAndRemovesWhenNil() throws {
        let suiteName = "PreferencesStoreTests.CharacterIntroDate.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserDefaultsPreferences(defaults: defaults)
        let introDate = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertNil(preferences.characterNotificationIntroDate)
        preferences.characterNotificationIntroDate = introDate
        XCTAssertEqual(defaults.object(forKey: "reminders.characterIntroDate") as? Double,
                       introDate.timeIntervalSince1970)
        XCTAssertEqual(UserDefaultsPreferences(defaults: defaults).characterNotificationIntroDate, introDate)

        preferences.characterNotificationIntroDate = nil
        XCTAssertNil(defaults.object(forKey: "reminders.characterIntroDate"))
        XCTAssertNil(preferences.characterNotificationIntroDate)
    }

    func testNotificationPreviewDelayDefaultsToFiveClampsAndKeepsItsKey() throws {
        let suiteName = "PreferencesStoreTests.PreviewDelay.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserDefaultsPreferences(defaults: defaults)

        XCTAssertEqual(preferences.notificationPreviewDelaySeconds, 5)

        preferences.notificationPreviewDelaySeconds = 14
        XCTAssertEqual(defaults.object(forKey: "dev.notificationPreviewDelay") as? Int, 14)
        XCTAssertEqual(UserDefaultsPreferences(defaults: defaults).notificationPreviewDelaySeconds, 14)

        preferences.notificationPreviewDelaySeconds = 0
        XCTAssertEqual(preferences.notificationPreviewDelaySeconds, 1)
        preferences.notificationPreviewDelaySeconds = 500
        XCTAssertEqual(preferences.notificationPreviewDelaySeconds, 20)

        defaults.set(-3, forKey: "dev.notificationPreviewDelay")
        XCTAssertEqual(preferences.notificationPreviewDelaySeconds, 1, "an out-of-range saved value is clamped on read")

        let inMemory = InMemoryPreferences()
        XCTAssertEqual(inMemory.notificationPreviewDelaySeconds, 5)
        inMemory.notificationPreviewDelaySeconds = 99
        XCTAssertEqual(inMemory.notificationPreviewDelaySeconds, 20)
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

        XCTAssertTrue(preferences.extraPersonableEnabled, "Extra Personable is on by default")
        XCTAssertNil(preferences.personaResetDate)
        XCTAssertFalse(preferences.personaIntroCardDismissed)
        let resetDate = Date(timeIntervalSince1970: 1_760_000_000)
        preferences.extraPersonableEnabled = false
        preferences.personaResetDate = resetDate
        preferences.personaIntroCardDismissed = true
        XCTAssertFalse(preferences.extraPersonableEnabled)
        XCTAssertEqual(preferences.personaResetDate, resetDate)
        XCTAssertTrue(preferences.personaIntroCardDismissed)
        preferences.personaResetDate = nil
        XCTAssertNil(preferences.personaResetDate)

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
        let expectedIntroDate = Date(timeIntervalSince1970: 1_750_000_000)
        preferences.characterNotificationIntroDate = expectedIntroDate

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
        XCTAssertEqual(preferences.characterNotificationIntroDate, expectedIntroDate)

        preferences.restPolicy = .fixed(seconds: 60)
        XCTAssertEqual(preferences.restPolicy, .fixed(seconds: 60))

        preferences.setGuideSeen(false, for: "contract_exercise")
        preferences.setExerciseTarget(nil, for: "contract_exercise")
        preferences.upNextOverride = nil
        preferences.characterNotificationIntroDate = nil
        XCTAssertFalse(preferences.guideSeen(for: "contract_exercise"))
        XCTAssertNil(preferences.exerciseTarget(for: "contract_exercise"))
        XCTAssertNil(preferences.upNextOverride)
        XCTAssertNil(preferences.characterNotificationIntroDate)
    }
}
