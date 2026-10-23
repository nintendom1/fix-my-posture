import Foundation

/// What iOS currently holds for this app's notifications, plus the notification code's own recent log.
/// Shown on the developer preview page and written to a file so it can be read off a connected iPhone.
struct NotificationDiagnosticsSnapshot: Equatable {
    struct Pending: Equatable {
        let identifier: String
        let title: String
        let body: String
        /// When iOS will deliver it, or nil when it has no upcoming date.
        let fireDate: Date?
    }

    struct Delivered: Equatable {
        let identifier: String
        let title: String
        let body: String
        let date: Date
    }

    /// One line per notification setting, such as "Lock Screen: enabled".
    let settings: [String]
    let pending: [Pending]
    let delivered: [Delivered]
    /// The newest lines of the event log, oldest first.
    let recentEvents: [String]
    let generatedAt: Date

    /// Pending requests that carry the character's reminders, in delivery order.
    var pendingReminders: [Pending] {
        pending.filter { $0.identifier.hasPrefix(WorkoutReminderScheduleBuilder.identifierPrefix) }
    }

    /// The whole snapshot as plain text.
    var report: String {
        var lines = ["Notification diagnostics at \(generatedAt.eventLogDescription)", "", "Settings:"]
        lines += settings.map { "  \($0)" }
        lines += ["", "Pending (\(pending.count)), soonest first:"]
        lines += pending.map { "  \($0.fireDate?.eventLogDescription ?? "no date") | \($0.identifier) | \($0.title) | \($0.body)" }
        lines += ["", "Delivered and still in Notification Center (\(delivered.count)):"]
        lines += delivered.map { "  \($0.date.eventLogDescription) | \($0.identifier) | \($0.title) | \($0.body)" }
        lines += ["", "Recent events (\(recentEvents.count)):"]
        lines += recentEvents.map { "  \($0)" }
        return lines.joined(separator: "\n") + "\n"
    }
}
