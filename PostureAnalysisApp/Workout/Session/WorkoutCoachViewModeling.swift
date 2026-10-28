import AdaptiveTraining
import AVFoundation
import Foundation
import Observation

/// The single value consumed by the HUD. Its fields are presentation data rather than a raw reducer.
struct WorkoutHUDViewState: Equatable {
    struct ExerciseOption: Equatable, Identifiable {
        let id: ExerciseID
        let displayName: String
    }

    let presentation: WorkoutHUDPresentation
    let visual: WorkoutVisualState
    let exercise: WorkoutHUDExercise?
    let exerciseID: ExerciseID?
    let exerciseOptions: [ExerciseOption]
    let planName: String?
    let isFollowingPlan: Bool
    let repCount: Int
    let sideReps: [BodySide: Int]
    let currentWeights: [ExerciseID: WorkoutWeight]
    let readings: [BodySide: ArmReading]
    let thresholds: [BodySide: ArmThresholds]
    let formReadings: [FormReading]
    let isPhoneTilted: Bool
    let micStatus: VoiceStatus
    let isMicMuted: Bool
    let heardPhrase: String?
    let isCoachMuted: Bool
    let showsMeasurements: Bool
    /// Shown only while a developer session recording runs.
    var recording: WorkoutRecordingHUD? = nil
}

/// The REC chip: tapping it drops a marker, and it briefly confirms each one.
struct WorkoutRecordingHUD: Equatable {
    var markerCount: Int
    /// "Marked 1:56", shown for a few seconds after a marker.
    var confirmation: String?

    /// Minutes and seconds since the recording began, such as "1:56".
    static func clockLabel(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.down)))
        return "\(whole / 60):\(String(format: "%02d", whole % 60))"
    }
}

enum WorkoutCameraStatus: Equatable {
    case idle
    case starting
    case running
    case interrupted
    case notAuthorized
    case failed(String)
}

@MainActor
protocol WorkoutCoachViewModeling: AnyObject, Observable {
    var hud: WorkoutHUDViewState { get }
    var overlay: WorkoutOverlayState? { get }
    var ghostFitOverlay: WorkoutOverlayState? { get }
    var guideMetrics: GuideMetrics? { get }
    var cameraStatus: WorkoutCameraStatus { get }
    var micStatus: VoiceStatus { get }
    var activeTip: CoachingTip? { get }
    var heardPhrase: String? { get }
    var session: WorkoutSession { get }
    var exercises: [ExerciseDefinition] { get }
    var captureSession: AVCaptureSession? { get }
    var hasOpened: Bool { get }
    var isCoachSpeaking: Bool { get }
    var isCoachMuted: Bool { get }
    var isMicMuted: Bool { get }
    var isHelpPresented: Bool { get }
    var isGuidePresented: Bool { get }
    /// Shared with the saved history record and any session recording.
    var workoutID: UUID { get }
    /// The "How was that?" question about the item that just finished; nil when none is open.
    var effortCard: EffortCardState? { get }

    func send(_ intent: WorkoutIntent)
    func onAppear(isApplicationActive: Bool)
    func onDisappear()
    func setApplicationActive(_ active: Bool)
    func startHoldProgress() -> Double?
    func rateEffort(_ effort: EffortFeedback)
    func skipEffort()
    /// Changes the card's amount by whole steps (1 rep or 5 seconds each).
    func adjustEffortAmount(by steps: Int)
}

extension WorkoutCoachViewModeling {
    /// The completion card or summary waits until the last item's question is answered or skipped.
    var showsCompletionCard: Bool { hud.visual.showsCompletionCard && effortCard == nil }
}
