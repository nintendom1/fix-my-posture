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
    /// Replaces every pending projected persona request (`PersonaNotificationRequest.projectedPrefix`) with `requests`.
    func replacePersonaRequests(_ requests: [PersonaNotificationRequest]) async
    /// Adds one immediate persona request (`PersonaNotificationRequest.immediatePrefix`). Reconciliation never removes it.
    func addPersonaRequest(_ request: PersonaNotificationRequest) async
    /// Removes every pending persona request, projected and immediate (Extra Personable off, Reset Persona).
    func removeAllPersonaRequests() async
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
    /// Reset Persona: sets the reset date, clears persona traces, keeps history and the Extra Personable setting.
    func resetPersona() async
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

    /// Replaces pending projected persona requests; immediate ones (`immediatePrefix`) stay.
    func replacePersonaRequests(_ requests: [PersonaNotificationRequest]) async {
        let pending = await center.pendingNotificationRequests()
        let oldIdentifiers = pending.map(\.identifier).filter { $0.hasPrefix(PersonaNotificationRequest.projectedPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: oldIdentifiers)
        var refusedCount = 0
        for request in requests where !(await add(request)) {
            refusedCount += 1
        }
        eventLog.record("persona: removed \(oldIdentifiers.count) projected, added \(requests.count), refused \(refusedCount)")
    }

    func addPersonaRequest(_ request: PersonaNotificationRequest) async {
        center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
        if await add(request) {
            eventLog.record("persona: queued \(request.identifier) (\(request.interruption.rawValue))")
        }
    }

    func removeAllPersonaRequests() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(PersonaNotificationRequest.identifierPrefix) }
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        eventLog.record("persona: removed \(identifiers.count) pending persona requests")
    }

    /// Adds one persona request. Persona notifications are Active or Passive, never Time Sensitive.
    private func add(_ request: PersonaNotificationRequest) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.categoryIdentifier = request.categoryIdentifier
        content.threadIdentifier = PersonaNotificationRequest.identifierPrefix
        content.userInfo = request.userInfo
        content.interruptionLevel = Self.interruptionLevel(for: request.interruption)
        content.sound = request.interruption == .active ? .default : nil
        if let imageAssetName = request.imageAssetName,
           let attachment = NotificationAttachmentFactory.makeAttachment(assetName: imageAssetName) {
            content.attachments = [attachment]
        }
        let trigger: UNNotificationTrigger
        switch request.trigger {
        case .after(let seconds):
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, seconds)), repeats: false)
        case .at(let components):
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }
        do {
            try await center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
            return true
        } catch {
            eventLog.record("persona: iOS refused \(request.identifier): \(error.localizedDescription)")
            return false
        }
    }

    static func interruptionLevel(for interruption: NotificationInterruption) -> UNNotificationInterruptionLevel {
        switch interruption {
        case .active: .active
        case .passive: .passive
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
    private var pendingEngagement: [PersonaEngagementEvent] = []
    private var engagementHandler: ((PersonaEngagementEvent) -> Void)?

    /// Internal so tests can exercise buffering without the shared instance; the app uses `shared`.
    init() {}

    /// Installs the persona engagement recorder and delivers any taps or dismissals buffered before launch finished.
    func installEngagement(handler: @escaping (PersonaEngagementEvent) -> Void) {
        engagementHandler = handler
        let buffered = pendingEngagement
        pendingEngagement = []
        buffered.forEach(handler)
    }

    func receive(engagement: PersonaEngagementEvent) {
        guard let engagementHandler else {
            pendingEngagement.append(engagement)
            return
        }
        engagementHandler(engagement)
    }

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
        NotificationCategoryRegistrar.register()
        return true
    }

    /// Called only while the app is open. Without this, iOS delivers the notification silently.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let content = notification.request.content
        completionHandler(Self.foregroundPresentation(
            forCategory: content.categoryIdentifier,
            interruptionLevel: content.interruptionLevel
        ))
    }

    /// Acknowledgments and persona notifications show over the app; passive persona notifications stay silent.
    static func foregroundPresentation(
        forCategory categoryIdentifier: String,
        interruptionLevel: UNNotificationInterruptionLevel = .active
    ) -> UNNotificationPresentationOptions {
        guard NotificationCategory.showsInForeground(categoryIdentifier) else { return [] }
        if categoryIdentifier == NotificationCategory.persona && interruptionLevel == .passive {
            return [.banner, .list]
        }
        return [.banner, .list, .sound]
    }

    /// Only opening a notification routes to its workout; a dismissal never does.
    static func shouldRouteToWorkout(actionIdentifier: String) -> Bool {
        actionIdentifier == UNNotificationDefaultActionIdentifier
    }

    /// A persona tap or dismissal as an engagement event, or nil for other notifications and actions.
    static func personaEngagement(
        categoryIdentifier: String,
        actionIdentifier: String,
        userInfo: [AnyHashable: Any],
        date: Date
    ) -> PersonaEngagementEvent? {
        guard categoryIdentifier == NotificationCategory.persona,
              let traceText = userInfo[PersonaNotificationRequest.UserInfoKey.traceID] as? String,
              let traceID = UUID(uuidString: traceText),
              let key = userInfo[PersonaNotificationRequest.UserInfoKey.observationKey] as? String else { return nil }
        let kind: PersonaEngagementEvent.Kind
        switch actionIdentifier {
        case UNNotificationDefaultActionIdentifier: kind = .tapped
        case UNNotificationDismissActionIdentifier: kind = .dismissed
        default: return nil
        }
        return PersonaEngagementEvent(traceID: traceID, observationKey: key, kind: kind, date: date)
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
        let content = response.notification.request.content
        let engagement = Self.personaEngagement(
            categoryIdentifier: content.categoryIdentifier,
            actionIdentifier: response.actionIdentifier,
            userInfo: content.userInfo,
            date: Date()
        )
        let target = Self.shouldRouteToWorkout(actionIdentifier: response.actionIdentifier)
            ? Self.workoutTarget(from: content.userInfo)
            : nil
        // A dismissal can wake the app in the background; finish the work before telling iOS we are done.
        Task { @MainActor in
            if let engagement { WorkoutReminderNotificationBridge.shared.receive(engagement: engagement) }
            if let target { WorkoutReminderNotificationBridge.shared.receive(target) }
            completionHandler()
        }
    }
}
