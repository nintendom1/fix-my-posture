import Foundation

/// Calendar-based rules for the user's configured workout schedule.
enum PlannedDays {
    /// Tests whether the calendar day matches the active recurrence.

    static func isPlanned(_ day: Date, settings: WorkoutReminderSettings, calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: day)
        switch settings.recurrence {
        case .daily: return true
        case .weekly: return settings.weekdays.contains(calendar.component(.weekday, from: day))
        case .everyOtherDay:
            let anchor = calendar.startOfDay(for: settings.everyOtherDayStartDate)
            guard day >= anchor else { return false }
            let days = calendar.dateComponents([.day], from: anchor, to: day).day ?? -1
            return days >= 0 && days.isMultiple(of: 2)
        }
    }

    /// Returns planned calendar days contained in a closed date range.
    static func list(in range: ClosedRange<Date>, settings: WorkoutReminderSettings, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var day = calendar.startOfDay(for: range.lowerBound)
        let end = calendar.startOfDay(for: range.upperBound)
        while day <= end {
            if isPlanned(day, settings: settings, calendar: calendar) { result.append(day) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }
}
