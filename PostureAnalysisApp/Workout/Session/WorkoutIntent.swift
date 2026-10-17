import Foundation

/// A touch or presentation action from the camera screen.
enum WorkoutIntent: Equatable {
    case start
    case pause
    case resume
    case restartSet
    case nextSet
    case changeExercise
    case chooseExercise(ExerciseID)
    case cancelExerciseChange
    case anotherRound
    case nextExercise
    case endWorkout
    case toggleCoachMute
    case setCoachMuted(Bool)
    case toggleMicrophoneMute
    case setMicrophoneMuted(Bool)
    case microphoneTapped
    case showGuide
    case hideGuide
    case readGuideAloud
    case stopSpeaking
    case showVoiceHelp
    case hideVoiceHelp
    case retryVoice
    case toggleMeasurements
    case dismissTip
    /// The view owns history persistence and SwiftUI dismissal for this action.
    case closeWorkout
    /// The view owns the system Settings URL for this action.
    case openSettings

    var command: WorkoutCommand? {
        switch self {
        case .start: return .start
        case .pause: return .pause
        case .resume: return .resume
        case .restartSet: return .restartSet
        case .nextSet: return .nextSet
        case .changeExercise: return .changeExercise
        case .chooseExercise(let id): return .selectExercise(id)
        case .cancelExerciseChange: return .cancel
        case .anotherRound: return .anotherRound
        case .nextExercise: return .nextExercise
        case .endWorkout: return .endWorkout
        default: return nil
        }
    }
}
