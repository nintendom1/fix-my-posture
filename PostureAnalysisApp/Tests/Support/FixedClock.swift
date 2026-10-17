import Foundation

struct FixedClock {
    static let timeZone = TimeZone(identifier: "America/Los_Angeles")!

    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "en_US_POSIX")
        value.timeZone = timeZone
        value.firstWeekday = 2
        return value
    }

    static let date: Date = {
        var calendar = Self.calendar
        return calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: 2026,
            month: 10,
            day: 16,
            hour: 9,
            minute: 41
        ))!
    }()
}
