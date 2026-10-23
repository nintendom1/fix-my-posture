import XCTest
@testable import PostureAnalysisApp

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testSettingTogglesReadAndWriteTheirExistingPreferenceKeys() {
        let suiteName = "SettingsViewModelTests.Toggles.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: PreferenceKey.workoutCoachCoachMuted)
        defaults.set(true, forKey: PreferenceKey.workoutCoachMicMuted)
        defaults.set(false, forKey: PreferenceKey.startByHolding)
        defaults.set(false, forKey: PreferenceKey.tiltWarningsEnabled)
        defaults.set(false, forKey: PreferenceKey.cameraTiltCompensationEnabled)
        defaults.set(false, forKey: PreferenceKey.showHorizonLine)
        defaults.set(false, forKey: PreferenceKey.showAlignmentTargets)
        let preferences = UserDefaultsPreferences(defaults: defaults)

        let viewModel = makeViewModel(preferences: preferences)

        XCTAssertFalse(viewModel.spokenCoachingEnabled)
        XCTAssertFalse(viewModel.voiceCommandsEnabled)
        XCTAssertFalse(viewModel.startByHoldingEnabled)
        XCTAssertFalse(viewModel.tiltWarningsEnabled)
        XCTAssertFalse(viewModel.cameraTiltCompensationEnabled)
        XCTAssertFalse(viewModel.showHorizonLine)
        XCTAssertFalse(viewModel.showAlignmentTargets)

        viewModel.spokenCoachingEnabled = true
        viewModel.voiceCommandsEnabled = true
        viewModel.startByHoldingEnabled = true
        viewModel.tiltWarningsEnabled = true
        viewModel.cameraTiltCompensationEnabled = true
        viewModel.showHorizonLine = true
        viewModel.showAlignmentTargets = true

        XCTAssertEqual(defaults.object(forKey: PreferenceKey.workoutCoachCoachMuted) as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: PreferenceKey.workoutCoachMicMuted) as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: PreferenceKey.startByHolding) as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: PreferenceKey.tiltWarningsEnabled) as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: PreferenceKey.cameraTiltCompensationEnabled) as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: PreferenceKey.showHorizonLine) as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: PreferenceKey.showAlignmentTargets) as? Bool, true)
    }

    func testRestPolicyAndWeightUnitPagesStoreSelectedValues() {
        let preferences = InMemoryPreferences()
        let viewModel = makeViewModel(preferences: preferences)

        viewModel.restPolicy = .fixed(seconds: 60)
        viewModel.weightUnit = .kg

        XCTAssertEqual(preferences.restPolicy, .fixed(seconds: 60))
        XCTAssertEqual(preferences.weightUnit, .kg)
        XCTAssertEqual(viewModel.restPolicy, .fixed(seconds: 60))
        XCTAssertEqual(viewModel.weightUnit, .kg)
    }

    func testWorkoutSettingRowsExposeTheirCurrentValues() {
        let preferences = InMemoryPreferences()
        let viewModel = makeViewModel(preferences: preferences)

        XCTAssertEqual(viewModel.restPolicyLabel, "Exercise default")
        XCTAssertEqual(viewModel.weightUnitLabel, "lb")
        XCTAssertTrue(viewModel.startByHoldingEnabled)

        viewModel.restPolicy = .fixed(seconds: 60)
        viewModel.weightUnit = .kg
        viewModel.startByHoldingEnabled = false

        XCTAssertEqual(viewModel.restPolicyLabel, "60 s")
        XCTAssertEqual(viewModel.weightUnitLabel, "kg")
        XCTAssertFalse(viewModel.startByHoldingEnabled)
    }

    func testCameraFramingRefreshRateStoresSelectedValue() {
        let preferences = InMemoryPreferences()
        let viewModel = makeViewModel(preferences: preferences)

        viewModel.feedbackRefreshRate = 10

        XCTAssertEqual(preferences.feedbackRefreshRate, 10)
        XCTAssertEqual(viewModel.feedbackRefreshRate, 10)
    }

    func testWorkoutReminderSettingsPersistAndShowTheirSummary() {
        let preferences = InMemoryPreferences()
        let viewModel = makeViewModel(preferences: preferences)

        XCTAssertFalse(viewModel.workoutRemindersEnabled)
        XCTAssertEqual(viewModel.workoutRemindersValue, "Off")

        viewModel.updateReminderSettings {
            $0.enabled = true
            $0.recurrence = .weekly
            $0.weekdays = [2, 4, 6]
            $0.hour = 18
            $0.minute = 0
        }

        XCTAssertTrue(viewModel.workoutRemindersEnabled)
        XCTAssertTrue(viewModel.workoutRemindersValue.hasPrefix("Mon, Wed, Fri · "))
        XCTAssertEqual(preferences.workoutReminderSettings, viewModel.workoutReminderSettings)
    }

    func testChangingReminderStylePersistsAndReconciles() {
        let preferences = InMemoryPreferences()
        preferences.workoutReminderSettings = WorkoutReminderSettings(
            enabled: true,
            style: .character
        )
        let reminderManager = MemoryWorkoutReminderManager()
        let viewModel = SettingsViewModel(
            preferences: preferences,
            router: AppRouter(),
            reminderManager: reminderManager
        )

        viewModel.updateReminderSettings { $0.style = .plain }

        XCTAssertEqual(preferences.workoutReminderSettings.style, .plain)
        XCTAssertEqual(viewModel.workoutReminderSettings.style, .plain)
        XCTAssertEqual(reminderManager.reconcileCount, 1)
    }

    func testSwitchingToEveryOtherDayStartsTheCadenceToday() {
        let preferences = InMemoryPreferences()
        preferences.workoutReminderSettings = WorkoutReminderSettings(
            enabled: true,
            recurrence: .daily,
            everyOtherDayStartDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let viewModel = makeViewModel(preferences: preferences)

        viewModel.selectReminderRecurrence(.everyOtherDay)

        XCTAssertEqual(viewModel.workoutReminderSettings.recurrence, .everyOtherDay)
        XCTAssertEqual(
            preferences.workoutReminderSettings.everyOtherDayStartDate,
            Calendar.current.startOfDay(for: Date())
        )
    }

    func testSettingsPagesAcknowledgementsAndDiagnosticsHaveRoutes() {
        let viewModel = makeViewModel()
        let destinations: [SettingsDestination] = [
            .voiceCommandsHelp,
            .restPolicy,
            .weightUnit,
            .workoutReminders,
            .cameraAndFraming,
            .postureDisplay,
            .privacy,
            .about,
            .acknowledgements,
            .developerDiagnostics,
            .notificationPreview
        ]

        for destination in destinations {
            viewModel.navigate(to: destination)
        }

        XCTAssertEqual(viewModel.path, destinations)
    }

    func testLatestAssessmentDiagnosticsLinkDismissesSettingsAndOpensAssessment() {
        let router = AppRouter()
        let assessmentID = UUID()
        router.open(.settings)
        let viewModel = SettingsViewModel(
            preferences: InMemoryPreferences(),
            router: router,
            latestAssessmentID: assessmentID
        )

        viewModel.openLatestAssessment()

        XCTAssertNil(router.presentedFullScreenRoute)
        XCTAssertEqual(router.selectedTab, .posture)
        XCTAssertEqual(router.path(for: .posture), [.assessment(id: assessmentID)])
    }

    func testTiltWarningsDefaultOnAndPersistThroughUserDefaults() {
        let suiteName = "SettingsViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = UserDefaultsPreferences(defaults: defaults)

        XCTAssertTrue(preferences.tiltWarningsEnabled)
        preferences.tiltWarningsEnabled = false
        XCTAssertFalse(UserDefaultsPreferences(defaults: defaults).tiltWarningsEnabled)
        XCTAssertEqual(defaults.object(forKey: PreferenceKey.tiltWarningsEnabled) as? Bool, false)
    }

    private func makeViewModel(
        preferences: any AppPreferencesStoring = InMemoryPreferences()
    ) -> SettingsViewModel {
        SettingsViewModel(preferences: preferences, router: AppRouter())
    }

    @MainActor
    private final class MemoryWorkoutReminderManager: WorkoutReminderManaging {
        private(set) var reconcileCount = 0

        func reconcile() {
            reconcileCount += 1
        }

        func workoutSaved(_ record: WorkoutRecord) {}

        func enable() async {}

        func authorizationStatus() async -> WorkoutReminderAuthorizationStatus { .authorized }
    }
}
