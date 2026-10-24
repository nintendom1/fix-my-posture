import UserNotifications

/// Registers the character notification categories. The persona category asks iOS to report dismissals
/// (`customDismissAction`) so engagement cooling can see them.
enum NotificationCategoryRegistrar {
    static func categories() -> Set<UNNotificationCategory> {
        // Implemented by P6.
        []
    }

    static func register(center: UNUserNotificationCenter = .current()) {
        // Implemented by P6.
    }
}
