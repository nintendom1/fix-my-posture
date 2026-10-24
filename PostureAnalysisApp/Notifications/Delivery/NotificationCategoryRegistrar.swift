import UserNotifications

/// Registers the character notification categories. Only the persona category asks iOS to report dismissals
/// (`customDismissAction`), so engagement cooling can see them; reminders and acknowledgments keep default behavior.
enum NotificationCategoryRegistrar {
    static func categories() -> Set<UNNotificationCategory> {
        [
            UNNotificationCategory(identifier: NotificationCategory.nudge, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: NotificationCategory.acknowledgment, actions: [], intentIdentifiers: []),
            UNNotificationCategory(
                identifier: NotificationCategory.persona,
                actions: [],
                intentIdentifiers: [],
                options: [.customDismissAction]
            ),
        ]
    }

    static func register(center: UNUserNotificationCenter = .current()) {
        center.setNotificationCategories(categories())
    }
}
