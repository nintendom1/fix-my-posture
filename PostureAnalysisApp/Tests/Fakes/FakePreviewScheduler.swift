import Foundation
@testable import PostureAnalysisApp

/// Records developer-preview notifications instead of sending them.
@MainActor
final class FakePreviewScheduler: NotificationPreviewScheduling {
    struct Failure: Error {}

    var status: WorkoutReminderAuthorizationStatus
    var error: Error?
    private(set) var authorizationRequestCount = 0
    private(set) var scheduled: [(content: CharacterNotificationContent, delay: TimeInterval)] = []

    init(status: WorkoutReminderAuthorizationStatus = .authorized) {
        self.status = status
    }

    func authorizationStatus() async -> WorkoutReminderAuthorizationStatus { status }

    func requestAuthorization() async -> WorkoutReminderAuthorizationStatus {
        authorizationRequestCount += 1
        if status == .notDetermined { status = .authorized }
        return status
    }

    func schedule(_ content: CharacterNotificationContent, after delay: TimeInterval) async throws -> String {
        if let error { throw error }
        scheduled.append((content, delay))
        return "preview-\(scheduled.count)"
    }
}
