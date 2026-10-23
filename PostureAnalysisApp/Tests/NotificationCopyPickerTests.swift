import XCTest
@testable import PostureAnalysisApp

final class NotificationCopyPickerTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }

    func testDeterministicAndNonnegative() {
        for day in [-100, 0, 100, 12_345] {
            let variant = NotificationCopyPicker.variant(
                scenarioID: "ordinary-daily-reminder", dayNumber: day, slotIndex: 2
            )
            XCTAssertGreaterThanOrEqual(variant, 0)
            XCTAssertEqual(variant, NotificationCopyPicker.variant(
                scenarioID: "ordinary-daily-reminder", dayNumber: day, slotIndex: 2
            ))
        }
    }

    func testEveryMultiLineCatalogScenarioChangesVariantOnConsecutiveDays() throws {
        let catalog = try NotificationScenarioCatalog.bundled(bundle: Bundle(for: AppEnvironment.self))
        let reference = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: reference)!
        let dayNumber = NotificationCopyPicker.dayNumber(for: reference, calendar: calendar)
        let nextDayNumber = NotificationCopyPicker.dayNumber(for: nextDay, calendar: calendar)
        for scenario in catalog.scenarios where scenario.copy.count > 1 {
            XCTAssertNotEqual(
                NotificationCopyPicker.variant(scenarioID: scenario.id, dayNumber: dayNumber, slotIndex: 0),
                NotificationCopyPicker.variant(scenarioID: scenario.id, dayNumber: nextDayNumber, slotIndex: 0),
                "\(scenario.id)"
            )
        }
    }
}
