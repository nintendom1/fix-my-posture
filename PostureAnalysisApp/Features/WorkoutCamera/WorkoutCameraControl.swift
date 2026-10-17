import Foundation

/// Camera-screen controls mapped to the existing intent boundary.
enum WorkoutCameraControl: Equatable {
    case primary
    case exerciseGuide
    case restartSet
    case nextSet
    case skipExercise
    case changeExercise
    case showMeasurements
    case coachMute
    case microphone
    case voiceCommands
    case endWorkout

    static func intent(for control: WorkoutCameraControl,
                       presentation: WorkoutHUDPresentation) -> WorkoutIntent? {
        switch control {
        case .primary: return presentation.primaryAction
        case .exerciseGuide: return .showGuide
        case .restartSet: return .restartSet
        case .nextSet: return .nextSet
        case .skipExercise: return .nextExercise
        case .changeExercise: return .changeExercise
        case .showMeasurements: return .toggleMeasurements
        case .coachMute: return .toggleCoachMute
        case .microphone: return .microphoneTapped
        case .voiceCommands: return .showVoiceHelp
        case .endWorkout: return .endWorkout
        }
    }
}
