import XCTest
@testable import PostureAnalysisApp

final class PersonaIntroCardTests: XCTestCase {
    @MainActor
    func testPersonaIntroVisibilityRequiresEveryPreferenceForBothTabs() {
        let makePreferences: () -> InMemoryPreferences = {
            let preferences = InMemoryPreferences()
            preferences.workoutReminderSettings = WorkoutReminderSettings(enabled: true, style: .character)
            preferences.extraPersonableEnabled = true
            preferences.personaIntroCardDismissed = false
            return preferences
        }

        let activePreferences = makePreferences()
        XCTAssertTrue(makeTrainViewModel(preferences: activePreferences).state.showsPersonaIntro)
        XCTAssertTrue(makePostureViewModel(preferences: activePreferences).state.showsPersonaIntro)

        let disabledReminders = makePreferences()
        disabledReminders.workoutReminderSettings.enabled = false
        assertIntroHidden(for: disabledReminders, reason: "reminders disabled")

        let plainStyle = makePreferences()
        plainStyle.workoutReminderSettings.style = .plain
        assertIntroHidden(for: plainStyle, reason: "Plain reminders")

        let extraPersonableOff = makePreferences()
        extraPersonableOff.extraPersonableEnabled = false
        assertIntroHidden(for: extraPersonableOff, reason: "Extra Personable disabled")

        let dismissed = makePreferences()
        dismissed.personaIntroCardDismissed = true
        assertIntroHidden(for: dismissed, reason: "card dismissed")
    }

    @MainActor
    func testDismissingOnTrainHidesCardOnPostureAfterItAppears() {
        let preferences = InMemoryPreferences()
        preferences.workoutReminderSettings = WorkoutReminderSettings(enabled: true, style: .character)
        let train = makeTrainViewModel(preferences: preferences)
        let posture = makePostureViewModel(preferences: preferences)
        XCTAssertTrue(train.state.showsPersonaIntro)
        XCTAssertTrue(posture.state.showsPersonaIntro)

        train.send(.dismissPersonaIntro)
        XCTAssertTrue(preferences.personaIntroCardDismissed)
        XCTAssertFalse(train.state.showsPersonaIntro)

        posture.send(.appeared)
        XCTAssertFalse(posture.state.showsPersonaIntro)
    }

    @MainActor
    func testOpenPersonaSettingsPresentsSettingsWithoutSwitchingTabs() {
        let preferences = InMemoryPreferences()
        let trainRouter = AppRouter()
        makeTrainViewModel(preferences: preferences, router: trainRouter).send(.openPersonaSettings)
        XCTAssertEqual(trainRouter.selectedTab, .train)
        XCTAssertEqual(trainRouter.presentedFullScreenRoute, .settings)

        let postureRouter = AppRouter(selectedTab: .posture)
        makePostureViewModel(preferences: preferences, router: postureRouter).send(.openPersonaSettings)
        XCTAssertEqual(postureRouter.selectedTab, .posture, "closing Settings returns to the Posture tab")
        XCTAssertEqual(postureRouter.presentedFullScreenRoute, .settings)
    }

    @MainActor
    func testIntroCardRendersWithItsActions() throws {
        _ = try SnapshotHost.render(
            PersonaIntroCard(onDismiss: {}, onOpenSettings: {}),
            frameId: "persona-intro-card",
            testCase: self
        )
    }

    @MainActor
    private func assertIntroHidden(for preferences: InMemoryPreferences, reason: String) {
        let train = makeTrainViewModel(preferences: preferences)
        let posture = makePostureViewModel(preferences: preferences)

        train.send(.appeared)
        posture.send(.appeared)

        XCTAssertFalse(train.state.showsPersonaIntro, "Train: \(reason)")
        XCTAssertFalse(posture.state.showsPersonaIntro, "Posture: \(reason)")
    }

    @MainActor
    private func makeTrainViewModel(
        preferences: InMemoryPreferences,
        router: AppRouter? = nil
    ) -> TrainHomeViewModel {
        TrainHomeViewModel(
            routines: nil,
            workoutHistory: nil,
            exerciseCatalog: LiveExerciseCatalog(),
            preferences: preferences,
            router: router ?? AppRouter(),
            now: { FixedClock.date },
            calendar: FixedClock.calendar
        )
    }

    @MainActor
    private func makePostureViewModel(
        preferences: InMemoryPreferences,
        router: AppRouter? = nil
    ) -> PostureHomeViewModel {
        PostureHomeViewModel(
            assessments: nil,
            images: nil,
            router: router ?? AppRouter(),
            preferences: preferences
        )
    }
}
