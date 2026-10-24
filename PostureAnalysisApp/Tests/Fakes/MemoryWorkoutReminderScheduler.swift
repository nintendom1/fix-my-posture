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
    private(set) var personaRequests: [PersonaNotificationRequest] = []
    private(set) var personaReplacementHistory: [[PersonaNotificationRequest]] = []
    var onReplacePersonaRequests: (() -> Void)?
    private(set) var immediatePersonaRequests: [PersonaNotificationRequest] = []
    private(set) var removeAllPersonaRequestsCount = 0
    var onAddPersonaRequest: (() -> Void)?

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

    /// Mirrors the system adapter: replaces pending projected persona requests and keeps immediate ones.
    func replacePersonaRequests(_ requests: [PersonaNotificationRequest]) async {
        personaRequests = personaRequests.filter { !$0.isProjected } + requests
        personaReplacementHistory.append(requests)
        onReplacePersonaRequests?()
    }

    func addPersonaRequest(_ request: PersonaNotificationRequest) async {
        personaRequests.removeAll { $0.identifier == request.identifier }
        personaRequests.append(request)
        immediatePersonaRequests.append(request)
        onAddPersonaRequest?()
    }

    func removeAllPersonaRequests() async {
        personaRequests = []
        removeAllPersonaRequestsCount += 1
    }
}
