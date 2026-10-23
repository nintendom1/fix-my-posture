import Foundation
@testable import PostureAnalysisApp

@MainActor
final class MemoryWorkoutReminderScheduler: WorkoutReminderScheduling {
    var status: WorkoutReminderAuthorizationStatus
    var requests: [WorkoutReminderNotificationRequest] = []
    private(set) var acknowledgments: [WorkoutAcknowledgmentRequest] = []
    private(set) var acknowledgmentHistory: [WorkoutAcknowledgmentRequest] = []
    private(set) var authorizationRequestCount = 0
    private(set) var replacementHistory: [[WorkoutReminderNotificationRequest]] = []
    var onReplaceRequests: (() -> Void)?
    var onScheduleAcknowledgment: (() -> Void)?

    init(status: WorkoutReminderAuthorizationStatus = .authorized) {
        self.status = status
    }

    func authorizationStatus() async -> WorkoutReminderAuthorizationStatus { status }

    func requestAuthorization() async -> WorkoutReminderAuthorizationStatus {
        authorizationRequestCount += 1
        if status == .notDetermined { status = .authorized }
        return status
    }

    func replaceRequests(_ requests: [WorkoutReminderNotificationRequest]) async {
        self.requests = requests
        replacementHistory.append(requests)
        onReplaceRequests?()
    }

    /// The system adapter keeps one acknowledgment pending, replacing it on each saved workout.
    func scheduleAcknowledgment(_ request: WorkoutAcknowledgmentRequest) async {
        acknowledgments = [request]
        acknowledgmentHistory.append(request)
        onScheduleAcknowledgment?()
    }
}
