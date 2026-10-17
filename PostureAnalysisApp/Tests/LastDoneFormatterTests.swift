import Foundation
import XCTest
@testable import PostureAnalysisApp

final class LastDoneFormatterTests: XCTestCase {
    private var calendar: Calendar { FixedClock.calendar }

    func testHeroLabelUsesToday() {
        XCTAssertEqual(
            LastDoneFormatter.heroLabel(for: date(2026, 10, 16), now: date(2026, 10, 16), calendar: calendar),
            "Today"
        )
    }

    func testHeroLabelUsesYesterday() {
        XCTAssertEqual(
            LastDoneFormatter.heroLabel(for: date(2026, 10, 15), now: date(2026, 10, 16), calendar: calendar),
            "Yesterday"
        )
    }

    func testHeroLabelUsesWeekdayWithinLastSevenDays() {
        XCTAssertEqual(
            LastDoneFormatter.heroLabel(for: date(2026, 10, 14), now: date(2026, 10, 16), calendar: calendar),
            "Wednesday"
        )
    }

    func testHeroLabelUsesMonthAndDayForOlderDates() {
        XCTAssertEqual(
            LastDoneFormatter.heroLabel(for: date(2026, 10, 7), now: date(2026, 10, 16), calendar: calendar),
            "Oct 7"
        )
    }

    func testYesterdayWorksAcrossYearBoundary() {
        XCTAssertEqual(
            LastDoneFormatter.heroLabel(for: date(2025, 12, 31), now: date(2026, 1, 1), calendar: calendar),
            "Yesterday"
        )
    }

    func testRoutineLabelUsesAbbreviatedWeekdayAndMonthDay() {
        XCTAssertEqual(
            LastDoneFormatter.routineLabel(for: date(2026, 10, 14), now: date(2026, 10, 16), calendar: calendar),
            "Last done Wed, Oct 14"
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}
