import Foundation
import UserNotifications

/// Sends one character notification after a short delay, for the developer preview.
@MainActor
protocol NotificationPreviewScheduling {
    func authorizationStatus() async -> WorkoutReminderAuthorizationStatus
    func requestAuthorization() async -> WorkoutReminderAuthorizationStatus
    /// Schedules the notification `delay` seconds from now and returns its request identifier.
    func schedule(_ content: CharacterNotificationContent, after delay: TimeInterval) async throws -> String
}

/// The only adapter that sends developer preview notifications.
///
/// Previews use the same content, category and image as real notifications, so they look and behave the same.
/// Their identifiers use their own prefix, so reminder reconciliation never removes them.
@MainActor
final class UserNotificationPreviewScheduler: NotificationPreviewScheduling {
    static let identifierPrefix = "fixMyPosture.devPreview."

    private let center: UNUserNotificationCenter
    private let authorization: UserNotificationWorkoutReminderScheduler

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        authorization = UserNotificationWorkoutReminderScheduler(center: center)
    }

    func authorizationStatus() async -> WorkoutReminderAuthorizationStatus {
        await authorization.authorizationStatus()
    }

    func requestAuthorization() async -> WorkoutReminderAuthorizationStatus {
        await authorization.requestAuthorization()
    }

    func schedule(_ content: CharacterNotificationContent, after delay: TimeInterval) async throws -> String {
        let notification = UNMutableNotificationContent()
        notification.title = content.title
        notification.body = content.body
        notification.sound = .default
        notification.categoryIdentifier = content.categoryIdentifier
        notification.threadIdentifier = Self.identifierPrefix
        if let attachment = NotificationAttachmentFactory.makeAttachment(assetName: content.imageAssetName) {
            notification.attachments = [attachment]
        }
        let identifier = Self.identifierPrefix + UUID().uuidString
        // A time-interval trigger must be greater than zero seconds.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier, content: notification, trigger: trigger))
        return identifier
    }
}
