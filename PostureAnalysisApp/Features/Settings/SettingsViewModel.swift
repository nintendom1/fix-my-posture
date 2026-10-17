import Foundation
import Observation
import UIKit

enum SettingsDestination: Hashable {
    case voiceCommandsHelp
    case restPolicy
    case weightUnit
    case workoutReminders
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

    var showAlignmentTargets: Bool {
        didSet { preferences.showAlignmentTargets = showAlignmentTargets }
    }

    var feedbackRefreshRate: Int {
        didSet { preferences.feedbackRefreshRate = feedbackRefreshRate }
    }

    var tiltWarningsEnabled: Bool {
        didSet { preferences.tiltWarningsEnabled = tiltWarningsEnabled }
    }

    var workoutReminderSettings: WorkoutReminderSettings {
        didSet {
            preferences.workoutReminderSettings = workoutReminderSettings.normalized()
            if !oldValue.enabled && workoutReminderSettings.enabled, let reminderManager {
                Task {
                    await reminderManager.enable()
                    await refreshReminderAuthorization()
                }
            } else {
                reminderManager?.reconcile()
            }
        }
    }

    private(set) var reminderAuthorization: WorkoutReminderAuthorizationStatus = .notDetermined

    let latestAssessmentID: UUID?

    private let preferences: any AppPreferencesStoring
    private let router: AppRouter
    private let reminderManager: (any WorkoutReminderManaging)?

    init(
        preferences: any AppPreferencesStoring,
        router: AppRouter,
        reminderManager: (any WorkoutReminderManaging)? = nil,
        latestAssessmentID: UUID? = nil
    ) {
        self.preferences = preferences
        self.router = router
        self.reminderManager = reminderManager
        self.latestAssessmentID = latestAssessmentID
        spokenCoachingEnabled = !preferences.workoutCoachCoachMuted
        voiceCommandsEnabled = !preferences.workoutCoachMicMuted
        restPolicy = preferences.restPolicy
        weightUnit = preferences.weightUnit
        startByHoldingEnabled = preferences.startByHolding
        cameraTiltCompensationEnabled = preferences.cameraTiltCompensationEnabled
        showHorizonLine = preferences.showHorizonLine
        showAlignmentTargets = preferences.showAlignmentTargets
        feedbackRefreshRate = preferences.feedbackRefreshRate
        tiltWarningsEnabled = preferences.tiltWarningsEnabled
        workoutReminderSettings = preferences.workoutReminderSettings
    }

    var workoutRemindersEnabled: Bool {
        get { workoutReminderSettings.enabled }
        set { updateReminderSettings { $0.enabled = newValue } }
    }

    var workoutRemindersValue: String {
        guard workoutRemindersEnabled else { return "Off" }
        if reminderAuthorization == .denied { return "Notifications off" }
        return workoutReminderSettings.summary
    }

    var restPolicyLabel: String {
        switch restPolicy {
        case .exerciseDefault:
            return "Exercise default"
        case .fixed(let seconds):
            return "\(seconds) s"
        }
    }

    var weightUnitLabel: String { weightUnit.rawValue }

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

    func updateReminderSettings(_ update: (inout WorkoutReminderSettings) -> Void) {
        var settings = workoutReminderSettings
        update(&settings)
        workoutReminderSettings = settings
    }

    func selectReminderRecurrence(_ recurrence: WorkoutReminderRecurrence) {
        updateReminderSettings { settings in
            // Switching into Every Other Day starts the cadence today, not on a date saved earlier.
            if recurrence == .everyOtherDay && settings.recurrence != .everyOtherDay {
                settings.everyOtherDayStartDate = Calendar.current.startOfDay(for: Date())
            }
            settings.recurrence = recurrence
        }
    }

    func refreshReminderAuthorization() async {
        guard let reminderManager else { return }
        reminderAuthorization = await reminderManager.authorizationStatus()
    }

    func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
