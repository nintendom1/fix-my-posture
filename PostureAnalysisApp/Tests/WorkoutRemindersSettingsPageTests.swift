import SwiftUI
import XCTest
@testable import PostureAnalysisApp

/// Render smoke tests for the Workout Reminders page. Set TEST_RUNNER_FMP_SNAPSHOT_DIR to also write PNGs.
@MainActor
final class WorkoutRemindersSettingsPageTests: XCTestCase {
    func testPageRendersTheStylePickerForEachStyle() throws {
        for style in WorkoutReminderStyle.allCases {
            let preferences = InMemoryPreferences()
            preferences.workoutReminderSettings = WorkoutReminderSettings(enabled: true, style: style)
            let viewModel = SettingsViewModel(preferences: preferences, router: AppRouter())
            viewModel.path = [.workoutReminders]

            let result = try SnapshotHost.render(
                SettingsScreen(viewModel: viewModel),
                frameId: "settings-reminders-\(style.rawValue)",
                testCase: self
            )

            XCTAssertGreaterThan(result.image.size.width, 0)
        }
    }
}
