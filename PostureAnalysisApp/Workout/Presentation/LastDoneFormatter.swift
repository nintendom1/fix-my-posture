import Foundation

/// Formats relative hero labels and absolute routine history labels using an explicit clock and calendar.
enum LastDoneFormatter {
    static func heroLabel(for date: Date, now: Date, calendar: Calendar) -> String {
        let startOfDate = calendar.startOfDay(for: date)
        let startOfNow = calendar.startOfDay(for: now)
        let daysAgo = calendar.dateComponents([.day], from: startOfDate, to: startOfNow).day

        switch daysAgo {
        case .some(0): return "Today"
        case .some(1): return "Yesterday"
        case .some(2...7): return formatted(date, pattern: "EEEE", calendar: calendar)
        default: return formatted(date, pattern: "MMM d", calendar: calendar)
        }
    }

    static func routineLabel(for date: Date, now: Date, calendar: Calendar) -> String {
        _ = now
        return "Last done " + formatted(date, pattern: "EEE, MMM d", calendar: calendar)
    }

    private static func formatted(_ date: Date, pattern: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
