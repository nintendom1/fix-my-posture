import AdaptiveTraining
import Foundation
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class AdaptiveInvitationPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testPolicyTableCoversStatusRouteCountAndSnoozeBoundaries() {
        let cases: [(String, TodaySessionStatus, Date?, Int, Bool, Bool)] = [
            ("initial setup", .needsCalibration, nil, 0, false, true),
            ("ready session", .ready(session()), nil, 0, false, false),
            ("completed session", .completedToday(family: .push, next: nil), nil, 0, false, false),
            ("nothing offered", .nothingOffered, nil, 0, false, false),
            ("before snooze end", .needsCalibration, now.addingTimeInterval(1), 0, false, false),
            ("at snooze end", .needsCalibration, now, 0, false, true),
            ("after snooze end", .needsCalibration, now.addingTimeInterval(-1), 0, false, true),
            ("below dismissal cap", .needsCalibration, nil, 2, false, true),
            ("at dismissal cap", .needsCalibration, nil, 3, false, false),
            ("full screen route", .needsCalibration, nil, 0, true, false)
        ]

        for (name, status, snoozedUntil, dismissCount, isPresentingFullScreen, expected) in cases {
            XCTAssertEqual(
                AdaptiveInvitationPolicy.shouldShow(
                    status: status,
                    snoozedUntil: snoozedUntil,
                    dismissCount: dismissCount,
                    isPresentingFullScreen: isPresentingFullScreen,
                    now: now
                ),
                expected,
                name
            )
        }
    }

    func testNotNowSnoozesSevenDaysAndTheThirdDismissalStopsShowing() throws {
        var currentDate = now
        let preferences = InMemoryPreferences()
        let provider = FakeInvitationProvider(status: .needsCalibration)
        let model = AdaptiveInvitationModel(
            preferences: preferences,
            provider: provider,
            router: AppRouter(),
            now: { currentDate }
        )

        for expectedCount in 1...AdaptiveInvitationPolicy.maxDismissals {
            model.evaluate(now: currentDate)
            XCTAssertTrue(model.isPresented)
            let dismissedAt = currentDate

            model.notNow()

            XCTAssertFalse(model.isPresented)
            XCTAssertEqual(preferences.adaptiveInvitationDismissCount, expectedCount)
            let snoozedUntil = try XCTUnwrap(preferences.adaptiveInvitationSnoozedUntil)
            XCTAssertEqual(snoozedUntil.timeIntervalSince(dismissedAt), 7 * 24 * 60 * 60, accuracy: 0.001)
            currentDate = snoozedUntil
        }

        model.evaluate(now: currentDate)
        XCTAssertFalse(model.isPresented)
    }

    func testAcceptOpensCalibrationAfterTheSheetDismissesWithoutCountingAsDismissal() {
        let preferences = InMemoryPreferences()
        let router = AppRouter()
        let fixedNow = now
        let model = AdaptiveInvitationModel(
            preferences: preferences,
            provider: FakeInvitationProvider(status: .needsCalibration),
            router: router,
            now: { fixedNow }
        )
        model.evaluate(now: now)

        model.accept()

        XCTAssertFalse(model.isPresented)
        XCTAssertNil(router.presentedFullScreenRoute)
        XCTAssertEqual(preferences.adaptiveInvitationDismissCount, 0)

        model.sheetDidDismiss()

        XCTAssertEqual(router.presentedFullScreenRoute, .calibration)
        XCTAssertEqual(preferences.adaptiveInvitationDismissCount, 0)
    }

    func testLeavingUnsavedCalibrationStaysHiddenUntilNextActivation() throws {
        let router = AppRouter()
        let fixedNow = now
        let model = AdaptiveInvitationModel(
            preferences: InMemoryPreferences(),
            provider: FakeInvitationProvider(status: .needsCalibration),
            router: router,
            now: { fixedNow }
        )
        model.evaluate(now: now)
        XCTAssertTrue(model.isPresented)

        model.accept()
        model.sheetDidDismiss()
        model.fullScreenRouteDidChange(to: router.presentedFullScreenRoute)
        XCTAssertEqual(router.presentedFullScreenRoute, .calibration)
        XCTAssertFalse(model.isPresented)

        router.dismissFullScreen()
        model.fullScreenRouteDidChange(to: router.presentedFullScreenRoute)
        XCTAssertFalse(model.isPresented, "The unsaved flow remains hidden in this app activation.")

        model.evaluate(now: now.addingTimeInterval(1))
        XCTAssertTrue(model.isPresented, "The next activation can invite again while setup is still needed.")

        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let shellURL = testsDirectory.deletingLastPathComponent().appendingPathComponent("App/AppShellView.swift")
        let shellSource = try String(contentsOf: shellURL, encoding: .utf8)
        let routeObserverRange = try XCTUnwrap(
            shellSource.range(of: ".onChange(of: router.presentedFullScreenRoute)")
        )
        let routeObserverSuffix = shellSource[routeObserverRange.lowerBound...]
        let routeObserverEnd = try XCTUnwrap(routeObserverSuffix.range(of: "\n        }"))
        let routeObserver = String(routeObserverSuffix[..<routeObserverEnd.upperBound])

        XCTAssertTrue(routeObserver.contains("fullScreenRouteDidChange(to: route)"))
        XCTAssertFalse(routeObserver.contains("adaptiveInvitation.evaluate"))
        XCTAssertEqual(
            shellSource.components(separatedBy: "environment.adaptiveInvitation.evaluate(now: Date())").count - 1,
            2
        )
    }

    func testNothingShowsWhileAWorkoutIsPresented() {
        let router = AppRouter()
        router.open(.workout(exerciseID: .wallPushUp, routineID: nil))
        let fixedNow = now
        let model = AdaptiveInvitationModel(
            preferences: InMemoryPreferences(),
            provider: FakeInvitationProvider(status: .needsCalibration),
            router: router,
            now: { fixedNow }
        )

        model.evaluate(now: now)

        XCTAssertFalse(model.isPresented)
    }

    func testInvitationCopyListAndWordingScanCoverTheSheetStrings() throws {
        XCTAssertEqual(AdaptiveInvitationCopy.all, [
            "Adaptive Training",
            "Find a comfortable starting point in a few minutes. A few tiny samples, then a short session each day.",
            "Find your starting point",
            "Not now"
        ])
        let forbiddenWords: Set<String> = [
            "test", "tests", "score", "scores", "level", "levels", "beginner", "beginners", "medical",
            "pain", "injury", "diagnosis", "doctor", "therapy", "symptom", "condition", "treatment", "scoliosis"
        ]
        for copy in AdaptiveInvitationCopy.all {
            let words = copy.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
            XCTAssertTrue(words.allSatisfy { !forbiddenWords.contains($0) }, copy)
        }

        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sourceURL = testsDirectory.deletingLastPathComponent()
            .appendingPathComponent("Features/Train/AdaptiveInvitationSheet.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let code = source.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let pattern = try NSRegularExpression(pattern: "\"((?:[^\"\\\\\\n]|\\\\.)*)\"")
        let range = NSRange(code.startIndex..., in: code)
        let literals = pattern.matches(in: code, range: range).compactMap { match in
            Range(match.range(at: 1), in: code).map { String(code[$0]) }
        }
        XCTAssertFalse(literals.isEmpty)
        for literal in literals {
            let words = literal.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
            XCTAssertTrue(words.allSatisfy { !forbiddenWords.contains($0) }, literal)
        }
    }

    private func session() -> TodaySession {
        TodaySession(
            family: .push,
            main: RungDose(variant: VariantID(rawValue: "push.wall_push_up"), dose: .reps(4)),
            harderSample: nil,
            offersBonus: false,
            isTiny: true,
            confidence: .low,
            estimatedSeconds: 60,
            rationale: "",
            basedOnTransitionID: nil
        )
    }
}

@MainActor
private final class FakeInvitationProvider: TodaySessionHeroProviding {
    let statusValue: TodaySessionStatus
    var lastStartProblem: String?

    init(status: TodaySessionStatus) {
        statusValue = status
    }

    func status(asOf now: Date) -> TodaySessionStatus { statusValue }
    func displayName(of variant: VariantID) -> String { variant.rawValue }
    func start(asOf now: Date) -> TodaySessionLaunch? { nil }
}
