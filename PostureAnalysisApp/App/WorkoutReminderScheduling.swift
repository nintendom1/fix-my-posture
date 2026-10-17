import UIKit
import UserNotifications

enum WorkoutReminderAuthorizationStatus: Equatable {
    case notDetermined
    case authorized
    case denied
}

@MainActor
protocol WorkoutReminderScheduling {
    func authorizationStatus() async -> WorkoutReminderAuthorizationStatus
    func requestAuthorization() async -> WorkoutReminderAuthorizationStatus
    func replaceRequests(_ requests: [WorkoutReminderNotificationRequest]) async
}

@MainActor
protocol WorkoutReminderReconciliation: AnyObject {
    func reconcile()
}

@MainActor
protocol WorkoutReminderManaging: WorkoutReminderReconciliation {
    func enable() async
    func authorizationStatus() async -> WorkoutReminderAuthorizationStatus
}

/// The only adapter that talks to UserNotifications for workout reminders.
@MainActor
final class UserNotificationWorkoutReminderScheduler: WorkoutReminderScheduling {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> WorkoutReminderAuthorizationStatus {
        let settings = await center.notificationSettings()
        return Self.map(settings.authorizationStatus)
    }

    func requestAuthorization() async -> WorkoutReminderAuthorizationStatus {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return await authorizationStatus()
        }
        return await authorizationStatus()
    }

    func replaceRequests(_ requests: [WorkoutReminderNotificationRequest]) async {
        let pending = await center.pendingNotificationRequests()
        let oldIdentifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(WorkoutReminderScheduleBuilder.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: oldIdentifiers)

        for request in requests {
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.sound = .default
            content.threadIdentifier = WorkoutReminderScheduleBuilder.identifierPrefix
            content.userInfo = request.target.payload
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: request.dateComponents,
                repeats: request.repeats
            )
            do {
                try await center.add(UNNotificationRequest(
                    identifier: request.identifier,
                    content: content,
                    trigger: trigger
                ))
            } catch {
                // A later app activation or settings change retries the bounded schedule.
            }
        }
    }

    private static func map(_ status: UNAuthorizationStatus) -> WorkoutReminderAuthorizationStatus {
        switch status {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .authorized, .provisional, .ephemeral:
            .authorized
        @unknown default:
            .denied
        }
    }
}

/// Buffers a notification tap until the app's composition root has created its router.
@MainActor
final class WorkoutReminderNotificationBridge {
    static let shared = WorkoutReminderNotificationBridge()

    private var pendingTarget: WorkoutReminderTarget?
    private var handler: ((WorkoutReminderTarget) -> Void)?

    private init() {}

    func install(handler: @escaping (WorkoutReminderTarget) -> Void) {
        self.handler = handler
        guard let pendingTarget else { return }
        self.pendingTarget = nil
        handler(pendingTarget)
    }

    func receive(_ target: WorkoutReminderTarget) {
        guard let handler else {
            pendingTarget = target
            return
        }
        handler(target)
    }
}

/// Installed before the SwiftUI scene launches so cold-start notification taps are delivered.
final class WorkoutReminderAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let target = WorkoutReminderTarget(userInfo: response.notification.request.content.userInfo)
        if let target {
            Task { @MainActor in
                WorkoutReminderNotificationBridge.shared.receive(target)
            }
        }
        completionHandler()
    }
}
