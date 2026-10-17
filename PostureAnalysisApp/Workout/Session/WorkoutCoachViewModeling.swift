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

    func send(_ intent: WorkoutIntent)
    func onAppear(isApplicationActive: Bool)
    func onDisappear()
    func setApplicationActive(_ active: Bool)
    func startHoldProgress() -> Double?
}
