import Foundation
import XCTest
@testable import PostureAnalysisApp

final class NotificationContentBuilderTests: XCTestCase {
    func testTemplateFillsKnownTokensAndKeepsOtherText() {
        let values: NotificationValues = [.streak: "26", .record: "31"]

        XCTAssertEqual(NotificationTemplate.render("{streak} days and you’re leaving me?", values: values),
                       "26 days and you’re leaving me?")
        XCTAssertEqual(NotificationTemplate.render("{streak}/{record}", values: values), "26/31")
        XCTAssertEqual(NotificationTemplate.render("{streak}{record}", values: values), "2631")
        XCTAssertEqual(NotificationTemplate.render("There we go.", values: values), "There we go.")
        XCTAssertEqual(NotificationTemplate.render("", values: values), "")
    }

    func testTemplateFailsRatherThanShowingAPlaceholder() {
        let values: NotificationValues = [.streak: "26"]

        XCTAssertNil(NotificationTemplate.render("{days} days", values: values), "no value for the token")
        XCTAssertNil(NotificationTemplate.render("{streek} days", values: values), "unknown token")
        XCTAssertNil(NotificationTemplate.render("{streak days", values: values), "unclosed brace")
    }

    func testVariantPicksCopyAndArtAndWrapsAround() {
        let scenario = makeScenario(copy: ["one", "two", "three"], art: [
            .init(expression: "smile", outfit: "hoodie", crop: .portrait),
            .init(expression: "normal", outfit: "hoodie", crop: .portrait)
        ])

        func content(_ variant: Int) -> CharacterNotificationContent? {
            NotificationContentBuilder.make(scenario: scenario, variant: variant, values: [:])
        }

        XCTAssertEqual(content(0)?.body, "one")
        XCTAssertEqual(content(1)?.body, "two")
        XCTAssertEqual(content(2)?.body, "three")
        XCTAssertEqual(content(3)?.body, "one", "wraps past the end")
        XCTAssertEqual(content(-1)?.body, "three", "wraps below zero")
        XCTAssertEqual(content(0)?.imageAssetName, "NotificationCharacter/smile-hoodie-portrait")
        XCTAssertEqual(content(1)?.imageAssetName, "NotificationCharacter/normal-hoodie-portrait")
        XCTAssertEqual(content(2)?.imageAssetName, "NotificationCharacter/smile-hoodie-portrait")
        XCTAssertEqual(content(0)?.artLabel, "smile · hoodie · portrait")
    }

    func testTitleFallsBackWhenItsTokenHasNoValue() {
        let scenario = makeScenario(title: "{suggestion}", copy: ["Hi"])

        XCTAssertEqual(NotificationContentBuilder.make(scenario: scenario, variant: 0, values: [:])?.title,
                       NotificationContentBuilder.fallbackTitle)
        XCTAssertEqual(
            NotificationContentBuilder.make(scenario: scenario, variant: 0, values: [.suggestion: "Push Day"])?.title,
            "Push Day"
        )
    }

    func testCopyLinesThatCannotBeFilledAreSkipped() {
        let scenario = makeScenario(copy: ["{days} days away", "Welcome back"])

        let content = NotificationContentBuilder.make(scenario: scenario, variant: 0, values: [:])

        XCTAssertEqual(content?.body, "Welcome back")
        XCTAssertNil(NotificationContentBuilder.make(
            scenario: makeScenario(copy: ["{days} days away"]), variant: 0, values: [:]
        ))
    }

    func testCategoryFollowsTheScenarioKind() {
        let nudge = NotificationContentBuilder.make(scenario: makeScenario(kind: .nudge), variant: 0, values: [:])
        let acknowledgment = NotificationContentBuilder.make(scenario: makeScenario(kind: .acknowledgment), variant: 0, values: [:])

        XCTAssertEqual(nudge?.categoryIdentifier, NotificationCategory.nudge)
        XCTAssertEqual(acknowledgment?.categoryIdentifier, NotificationCategory.acknowledgment)
        XCTAssertNotEqual(NotificationCategory.nudge, NotificationCategory.acknowledgment)
    }

    func testOnlyAcknowledgmentsShowWhileTheAppIsOpen() {
        XCTAssertTrue(NotificationCategory.showsInForeground(NotificationCategory.acknowledgment))
        XCTAssertFalse(NotificationCategory.showsInForeground(NotificationCategory.nudge))
        XCTAssertFalse(NotificationCategory.showsInForeground(""))
        XCTAssertFalse(NotificationCategory.showsInForeground("somethingElse"))
    }

    func testAppDelegateOpensTheForegroundBannerOnlyForAcknowledgments() {
        XCTAssertEqual(
            WorkoutReminderAppDelegate.foregroundPresentation(forCategory: NotificationCategory.acknowledgment),
            [.banner, .list, .sound]
        )
        XCTAssertEqual(WorkoutReminderAppDelegate.foregroundPresentation(forCategory: NotificationCategory.nudge), [])
        XCTAssertEqual(WorkoutReminderAppDelegate.foregroundPresentation(forCategory: ""), [])
    }

    @MainActor
    func testAttachmentFactoryTurnsAnAssetIntoAPNGAttachment() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotificationAttachmentFactoryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let attachment = NotificationAttachmentFactory.makeAttachment(
            assetName: "NotificationCharacter/smile-hoodie-portrait",
            bundle: Bundle(for: AppEnvironment.self),
            directory: directory
        )

        XCTAssertNotNil(attachment)
        XCTAssertNil(NotificationAttachmentFactory.makeAttachment(
            assetName: "NotificationCharacter/no-such-image",
            bundle: Bundle(for: AppEnvironment.self),
            directory: directory
        ))
    }

    private func makeScenario(
        kind: NotificationScenario.Kind = .nudge,
        title: String = "Title",
        copy: [String] = ["Hello"],
        art: [NotificationScenario.Art] = [.init(expression: "smile", outfit: "hoodie", crop: .portrait)]
    ) -> NotificationScenario {
        NotificationScenario(id: "test", name: "Test", kind: kind, trigger: "t", tone: "t",
                             art: art, title: title, copy: copy, sample: [:])
    }
}
