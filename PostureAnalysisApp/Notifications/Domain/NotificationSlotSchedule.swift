import Foundation

/// Builds the local wall-clock notification slots for a planned day.
enum NotificationSlotSchedule {
    /// Returns valid slots in fire-time order, capped and spaced by the policy.
    static func slots(
        day: Date, settings: WorkoutReminderSettings, calendar: Calendar,
        policy: NotificationPolicy = .standard
    ) -> [(slot: NotificationSlot, time: Date)] {
        guard let reminder = date(
            on: day, hour: settings.hour, minute: settings.minute, calendar: calendar
        ) else { return [] }
        var result: [(slot: NotificationSlot, time: Date)] = [(.reminder, reminder)]
        guard let followUp = followUpTime(
            day: day, reminder: reminder, settings: settings, calendar: calendar, policy: policy
        ) else {
            appendFinalWarning(day: day, after: reminder, to: &result, calendar: calendar, policy: policy)
            return result
        }
        result.append((.followUp, followUp))
        appendFinalWarning(day: day, after: followUp, to: &result, calendar: calendar, policy: policy)
        return result
    }

    /// Computes T + delay as elapsed time, then caps it at the day's 21:00 wall-clock time.
    private static func followUpTime(
        day: Date, reminder: Date, settings: WorkoutReminderSettings,
        calendar: Calendar, policy: NotificationPolicy
    ) -> Date? {
        guard let delayed = calendar.date(byAdding: .hour, value: policy.followUpDelayHours, to: reminder),
              let latest = date(on: day, hour: policy.followUpLatestHour, minute: 0, calendar: calendar) else {
            return nil
        }
        let followUp = min(delayed, latest)
        guard followUp.timeIntervalSince(reminder) >= Double(policy.minimumSlotGapMinutes * 60) else {
            return nil
        }
        return followUp
    }

    /// Adds the final warning only when it is spaced from the previous valid slot.
    private static func appendFinalWarning(
        day: Date, after previous: Date, to result: inout [(slot: NotificationSlot, time: Date)],
        calendar: Calendar, policy: NotificationPolicy
    ) {
        guard let final = date(
            on: day, hour: policy.finalWarningHour, minute: policy.finalWarningMinute,
            calendar: calendar
        ), final.timeIntervalSince(previous) >= Double(policy.minimumSlotGapMinutes * 60) else { return }
        result.append((.finalWarning, final))
    }

    /// Makes a local date from day and clock components using the supplied calendar.
    private static func date(on day: Date, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)
    }
}
