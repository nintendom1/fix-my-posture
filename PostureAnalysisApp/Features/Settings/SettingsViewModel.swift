import Foundation
import Observation

enum SettingsDestination: Hashable {
    case voiceCommandsHelp
    case restPolicy
    case weightUnit
    case cameraAndFraming
    case postureDisplay
    case privacy
    case about
    case acknowledgements
    case developerDiagnostics
}

@MainActor
@Observable
final class SettingsViewModel {
    var path: [SettingsDestination] = []

    var spokenCoachingEnabled: Bool {
        didSet { preferences.workoutCoachCoachMuted = !spokenCoachingEnabled }
    }

    var voiceCommandsEnabled: Bool {
        didSet { preferences.workoutCoachMicMuted = !voiceCommandsEnabled }
    }

    var restPolicy: RestPolicy {
        didSet { preferences.restPolicy = restPolicy }
    }

    var weightUnit: PreferredWeightUnit {
        didSet { preferences.weightUnit = weightUnit }
    }

    var startByHoldingEnabled: Bool {
        didSet { preferences.startByHolding = startByHoldingEnabled }
    }

    var cameraTiltCompensationEnabled: Bool {
        didSet { preferences.cameraTiltCompensationEnabled = cameraTiltCompensationEnabled }
    }

    var showHorizonLine: Bool {
        didSet { preferences.showHorizonLine = showHorizonLine }
    }

    var feedbackRefreshRate: Int {
        didSet { preferences.feedbackRefreshRate = feedbackRefreshRate }
    }

    var tiltWarningsEnabled: Bool {
        didSet { preferences.tiltWarningsEnabled = tiltWarningsEnabled }
    }

    let latestAssessmentID: UUID?

    private let preferences: any AppPreferencesStoring
    private let router: AppRouter

    init(
        preferences: any AppPreferencesStoring,
        router: AppRouter,
        latestAssessmentID: UUID? = nil
    ) {
        self.preferences = preferences
        self.router = router
        self.latestAssessmentID = latestAssessmentID
        spokenCoachingEnabled = !preferences.workoutCoachCoachMuted
        voiceCommandsEnabled = !preferences.workoutCoachMicMuted
        restPolicy = preferences.restPolicy
        weightUnit = preferences.weightUnit
        startByHoldingEnabled = preferences.startByHolding
        cameraTiltCompensationEnabled = preferences.cameraTiltCompensationEnabled
        showHorizonLine = preferences.showHorizonLine
        feedbackRefreshRate = preferences.feedbackRefreshRate
        tiltWarningsEnabled = preferences.tiltWarningsEnabled
    }

    var workoutRemindersEnabled: Bool { false }
    var workoutRemindersValue: String { "Soon" }

    var restPolicyLabel: String {
        switch restPolicy {
        case .exerciseDefault:
            return "Exercise default"
        case .fixed(let seconds):
            return "\(seconds) s"
        }
    }

    func navigate(to destination: SettingsDestination) {
        path.append(destination)
    }

    func popToPreviousPage() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func done() {
        router.dismissFullScreen()
    }

    func openLatestAssessment() {
        guard let latestAssessmentID else { return }
        router.dismissFullScreen()
        router.open(.assessment(id: latestAssessmentID))
    }
}
