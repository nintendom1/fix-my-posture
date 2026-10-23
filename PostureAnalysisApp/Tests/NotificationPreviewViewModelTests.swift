import Foundation
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class NotificationPreviewViewModelTests: XCTestCase {
    func testSelectsTheFirstScenarioAndBuildsItsPreviewFromSampleValues() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.selectedID, "ordinary")
        XCTAssertEqual(viewModel.preview?.title, "Shoulder Day · about 12 min")
        XCTAssertEqual(viewModel.preview?.body, "Want to go?")
        XCTAssertEqual(viewModel.preview?.categoryIdentifier, NotificationCategory.nudge)
        XCTAssertEqual(viewModel.scenarios(of: .nudge).map(\.id), ["ordinary", "at-risk"])
        XCTAssertEqual(viewModel.scenarios(of: .acknowledgment).map(\.id), ["done"])
    }

    func testSelectingAScenarioResetsTheVariantAndFillsItsTokens() {
        let viewModel = makeViewModel()
        viewModel.stepVariant(by: 1)

        viewModel.select("at-risk")

        XCTAssertEqual(viewModel.selectedID, "at-risk")
        XCTAssertEqual(viewModel.variantIndex, 0)
        XCTAssertEqual(viewModel.preview?.title, "26-day streak")
        XCTAssertEqual(viewModel.preview?.body, "26 days and you’re leaving me?")
        XCTAssertEqual(viewModel.preview?.categoryIdentifier, NotificationCategory.nudge)

        viewModel.select("nope")
        XCTAssertEqual(viewModel.selectedID, "at-risk", "an unknown id is ignored")

        viewModel.select("done")
        XCTAssertEqual(viewModel.preview?.categoryIdentifier, NotificationCategory.acknowledgment)
    }

    func testVariantsStepThroughCopyAndArtAndWrapBothWays() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.variantCount, 2)
        viewModel.stepVariant(by: 1)
        XCTAssertEqual(viewModel.preview?.body, "Ready?")
        XCTAssertEqual(viewModel.preview?.imageAssetName, "NotificationCharacter/normal-hoodie-portrait")
        viewModel.stepVariant(by: 1)
        XCTAssertEqual(viewModel.variantIndex, 0)
        viewModel.stepVariant(by: -1)
        XCTAssertEqual(viewModel.variantIndex, 1)
    }

    func testDelayComesFromPreferencesIsClampedAndPersists() {
        let preferences = InMemoryPreferences()
        preferences.notificationPreviewDelaySeconds = 12
        let viewModel = makeViewModel(preferences: preferences)

        XCTAssertEqual(viewModel.delaySeconds, 12)

        viewModel.delaySeconds = 0
        XCTAssertEqual(viewModel.delaySeconds, 1)
        XCTAssertEqual(preferences.notificationPreviewDelaySeconds, 1)

        viewModel.delaySeconds = 99
        XCTAssertEqual(viewModel.delaySeconds, 20)
        XCTAssertEqual(preferences.notificationPreviewDelaySeconds, 20)

        viewModel.delaySeconds = 7
        XCTAssertEqual(preferences.notificationPreviewDelaySeconds, 7)
    }

    func testSendSchedulesTheShownNotificationAfterTheDelayAndCountsDown() async {
        let scheduler = FakePreviewScheduler()
        let preferences = InMemoryPreferences()
        preferences.notificationPreviewDelaySeconds = 3
        var states: [NotificationPreviewViewModel.SendState] = []
        var viewModel: NotificationPreviewViewModel!
        viewModel = makeViewModel(preferences: preferences, scheduler: scheduler, sleep: { duration in
            XCTAssertEqual(duration, .seconds(1))
            states.append(viewModel.sendState)
        })
        viewModel.select("at-risk")

        await viewModel.send()

        XCTAssertEqual(scheduler.scheduled.map(\.content), [viewModel.preview])
        XCTAssertEqual(scheduler.scheduled.map(\.delay), [3])
        XCTAssertEqual(states, [.countingDown(secondsRemaining: 3), .countingDown(secondsRemaining: 2),
                                .countingDown(secondsRemaining: 1)])
        XCTAssertEqual(viewModel.sendState, .sent)
        XCTAssertFalse(viewModel.isBusy)
        XCTAssertEqual(scheduler.authorizationRequestCount, 0)
    }

    func testSendRequestsPermissionOnlyWhenItHasNotBeenAsked() async {
        let scheduler = FakePreviewScheduler(status: .notDetermined)
        let viewModel = makeViewModel(scheduler: scheduler)

        await viewModel.send()

        XCTAssertEqual(scheduler.authorizationRequestCount, 1)
        XCTAssertEqual(scheduler.scheduled.count, 1)
        XCTAssertEqual(viewModel.authorization, .authorized)
        XCTAssertEqual(viewModel.sendState, .sent)
    }

    func testSendExplainsAndDoesNotScheduleWhenNotificationsAreOff() async {
        let scheduler = FakePreviewScheduler(status: .denied)
        let viewModel = makeViewModel(scheduler: scheduler)

        await viewModel.send()

        XCTAssertTrue(scheduler.scheduled.isEmpty)
        XCTAssertEqual(scheduler.authorizationRequestCount, 0)
        XCTAssertEqual(viewModel.authorization, .denied)
        XCTAssertEqual(viewModel.sendState, .failed("Notifications are turned off for Fix My Posture."))
        XCTAssertFalse(viewModel.isBusy)
    }

    func testSendReportsASchedulingFailure() async {
        let scheduler = FakePreviewScheduler()
        scheduler.error = FakePreviewScheduler.Failure()
        let viewModel = makeViewModel(scheduler: scheduler)

        await viewModel.send()

        XCTAssertEqual(viewModel.sendState, .failed("The notification could not be scheduled."))
        XCTAssertFalse(viewModel.isBusy)
    }

    func testASecondSendWhileOneIsRunningIsIgnored() async {
        let scheduler = FakePreviewScheduler()
        var viewModel: NotificationPreviewViewModel!
        var reentered = false
        viewModel = makeViewModel(scheduler: scheduler, sleep: { _ in
            guard !reentered else { return }
            reentered = true
            XCTAssertTrue(viewModel.isBusy)
            await viewModel.send()
        })

        await viewModel.send()

        XCTAssertEqual(scheduler.scheduled.count, 1)
    }

    func testChangingTheSelectionClearsAFinishedState() async {
        let viewModel = makeViewModel()
        await viewModel.send()
        XCTAssertEqual(viewModel.sendState, .sent)

        viewModel.stepVariant(by: 1)

        XCTAssertEqual(viewModel.sendState, .idle)
    }

    func testMissingScenarioDataShowsAnErrorAndSendsNothing() async {
        let scheduler = FakePreviewScheduler()
        let viewModel = NotificationPreviewViewModel(
            catalog: nil,
            loadError: "The data is missing.",
            preferences: InMemoryPreferences(),
            scheduler: scheduler,
            openSettings: {},
            sleep: { _ in }
        )

        await viewModel.send()

        XCTAssertEqual(viewModel.loadError, "The data is missing.")
        XCTAssertTrue(viewModel.scenarios.isEmpty)
        XCTAssertNil(viewModel.preview)
        XCTAssertTrue(scheduler.scheduled.isEmpty)
    }

    func testOpenNotificationSettingsUsesTheInjectedAction() {
        var opened = 0
        let viewModel = makeViewModel(openSettings: { opened += 1 })

        viewModel.openNotificationSettings()

        XCTAssertEqual(opened, 1)
    }

    // MARK: Helpers

    private func makeViewModel(
        preferences: any AppPreferencesStoring = InMemoryPreferences(),
        scheduler: FakePreviewScheduler? = nil,
        openSettings: @escaping () -> Void = {},
        sleep: @escaping (Duration) async -> Void = { _ in }
    ) -> NotificationPreviewViewModel {
        NotificationPreviewViewModel(
            catalog: try! NotificationScenarioCatalog(data: Self.catalogJSON),
            preferences: preferences,
            scheduler: scheduler ?? FakePreviewScheduler(),
            openSettings: openSettings,
            sleep: sleep
        )
    }

    private static let catalogJSON = Data("""
    {
      "version": 1,
      "sampleSuggestion": "Shoulder Day · about 12 min",
      "scenarios": [
        {"id": "ordinary", "name": "Ordinary", "kind": "nudge", "trigger": "t", "tone": "t",
         "art": [{"expression": "smile", "outfit": "hoodie", "crop": "portrait"},
                 {"expression": "normal", "outfit": "hoodie", "crop": "portrait"}],
         "title": "{suggestion}", "copy": ["Want to go?", "Ready?"], "sample": {}},
        {"id": "at-risk", "name": "At risk", "kind": "nudge", "trigger": "t", "tone": "t",
         "art": [{"expression": "sad", "outfit": "hoodie", "crop": "close"}],
         "title": "{streak}-day streak", "copy": ["{streak} days and you’re leaving me?", "Please."],
         "sample": {"streak": 26}},
        {"id": "done", "name": "Done", "kind": "acknowledgment", "trigger": "t", "tone": "t",
         "art": [{"expression": "smile2", "outfit": "hoodie", "crop": "portrait"}],
         "title": "Nice work", "copy": ["There we go."], "sample": {}}
      ]
    }
    """.utf8)
}
