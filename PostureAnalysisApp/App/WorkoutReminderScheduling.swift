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
    func scheduleAcknowledgment(_ request: WorkoutAcknowledgmentRequest) async
}

@MainActor
protocol WorkoutReminderReconciliation: AnyObject {
    func reconcile()
    func workoutSaved(_ record: WorkoutRecord)
}

extension WorkoutReminderReconciliation {
    func workoutSaved(_ record: WorkoutRecord) {}
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
    private let eventLog: any NotificationEventRecording

    init(
        center: UNUserNotificationCenter = .current(),
        eventLog: any NotificationEventRecording = NoNotificationEventLog()
    ) {
        self.center = center
        self.eventLog = eventLog
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

        var refusedCount = 0
        for request in requests {
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.sound = .default
            content.threadIdentifier = WorkoutReminderScheduleBuilder.identifierPrefix
            content.userInfo = request.target.payload
            if let categoryIdentifier = request.categoryIdentifier {
                content.categoryIdentifier = categoryIdentifier
            }
            if let imageAssetName = request.imageAssetName,
               let attachment = NotificationAttachmentFactory.makeAttachment(assetName: imageAssetName) {
                content.attachments = [attachment]
            }
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
                refusedCount += 1
                eventLog.record("replaceRequests: iOS refused \(request.identifier): \(error.localizedDescription)")
            }
        }
        let queued = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(WorkoutReminderScheduleBuilder.identifierPrefix) }
        eventLog.record(
            "replaceRequests: removed \(oldIdentifiers.count), asked iOS to add \(requests.count), "
                + "refused \(refusedCount), queued now \(queued.count)"
        )
    }

    /// Replaces any queued workout acknowledgment with the newest saved session response.
    func scheduleAcknowledgment(_ request: WorkoutAcknowledgmentRequest) async {
        let pending = await center.pendingNotificationRequests()
        let oldIdentifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(WorkoutAcknowledgmentRequest.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: oldIdentifiers)

        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.userInfo = [:]
        if let categoryIdentifier = request.categoryIdentifier {
            content.categoryIdentifier = categoryIdentifier
        }
        content.threadIdentifier = WorkoutAcknowledgmentRequest.identifierPrefix
        if let imageAssetName = request.imageAssetName,
           let attachment = NotificationAttachmentFactory.makeAttachment(assetName: imageAssetName) {
            content.attachments = [attachment]
        }
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(max(1, request.delaySeconds)),
            repeats: false
        )
        do {
            try await center.add(UNNotificationRequest(
                identifier: request.identifier,
                content: content,
                trigger: trigger
            ))
            eventLog.record("ack: queued \(request.identifier) to fire in \(request.delaySeconds)s")
        } catch {
            // A later saved workout can replace and retry the pending acknowledgment.
            eventLog.record("ack: iOS refused \(request.identifier): \(error.localizedDescription)")
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

    /// Called only while the app is open. Without this, iOS delivers the notification silently.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(Self.foregroundPresentation(forCategory: notification.request.content.categoryIdentifier))
    }

    static func foregroundPresentation(forCategory categoryIdentifier: String) -> UNNotificationPresentationOptions {
        NotificationCategory.showsInForeground(categoryIdentifier) ? [.banner, .list, .sound] : []
    }

    /// Returns nil for targetless notifications such as workout acknowledgments.
    static func workoutTarget(from userInfo: [AnyHashable: Any]) -> WorkoutReminderTarget? {
        WorkoutReminderTarget(userInfo: userInfo)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let target = Self.workoutTarget(from: response.notification.request.content.userInfo)
        if let target {
            Task { @MainActor in
                WorkoutReminderNotificationBridge.shared.receive(target)
            }
        }
        completionHandler()
    }
}
