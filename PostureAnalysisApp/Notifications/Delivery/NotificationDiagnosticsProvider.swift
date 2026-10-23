import Foundation
import UserNotifications

/// Reads what iOS holds for this app's notifications.
@MainActor
protocol NotificationDiagnosticsProviding {
    func snapshot() async -> NotificationDiagnosticsSnapshot
}

/// The only adapter that reads pending and delivered notifications and the notification settings.
@MainActor
final class UserNotificationDiagnosticsProvider: NotificationDiagnosticsProviding {
    private let center: UNUserNotificationCenter
    private let eventLog: FileNotificationEventLog
    private let now: () -> Date

    init(
        center: UNUserNotificationCenter = .current(),
        eventLog: FileNotificationEventLog,
        now: @escaping () -> Date = Date.init
    ) {
        self.center = center
        self.eventLog = eventLog
        self.now = now
    }

    func snapshot() async -> NotificationDiagnosticsSnapshot {
        let settings = await center.notificationSettings()
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        let pendingSummaries = pending.map { request in
            NotificationDiagnosticsSnapshot.Pending(
                identifier: request.identifier,
                title: request.content.title,
                body: request.content.body,
                fireDate: (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                    ?? (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
            )
        }
        .sorted { ($0.fireDate ?? .distantFuture) < ($1.fireDate ?? .distantFuture) }
        let deliveredSummaries = delivered.map { notification in
            NotificationDiagnosticsSnapshot.Delivered(
                identifier: notification.request.identifier,
                title: notification.request.content.title,
                body: notification.request.content.body,
                date: notification.date
            )
        }
        .sorted { $0.date > $1.date }
        return NotificationDiagnosticsSnapshot(
            settings: Self.settingLines(settings),
            pending: pendingSummaries,
            delivered: deliveredSummaries,
            recentEvents: eventLog.recentLines(40),
            generatedAt: now()
        )
    }

    private static func settingLines(_ settings: UNNotificationSettings) -> [String] {
        [
            "Permission: \(authorization(settings.authorizationStatus))",
            "Alerts: \(setting(settings.alertSetting))",
            "Lock Screen: \(setting(settings.lockScreenSetting))",
            "Notification Center: \(setting(settings.notificationCenterSetting))",
            "Sounds: \(setting(settings.soundSetting))",
            "Scheduled Summary: \(setting(settings.scheduledDeliverySetting))",
            "Alert style: \(alertStyle(settings.alertStyle))"
        ]
    }

    private static func authorization(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "not asked yet"
        case .denied: "denied"
        case .authorized: "authorized"
        case .provisional: "provisional"
        case .ephemeral: "ephemeral"
        @unknown default: "unknown"
        }
    }

    private static func setting(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .notSupported: "not supported"
        case .disabled: "disabled"
        case .enabled: "enabled"
        @unknown default: "unknown"
        }
    }

    private static func alertStyle(_ style: UNAlertStyle) -> String {
        switch style {
        case .none: "none"
        case .banner: "banner"
        case .alert: "alert"
        @unknown default: "unknown"
        }
    }
}
