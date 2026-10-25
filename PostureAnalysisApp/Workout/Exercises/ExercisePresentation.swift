import Foundation

/// A category used to filter exercises in the Library.
enum ExerciseFilterGroup: String, Hashable {
    case upper
    case lower
    case bodyweight
    case dumbbells
    case band
}

/// A named gradient from the exercise presentation design.
struct ExerciseGradient: Equatable {
    enum Token: String, Hashable {
        case press
        case lateralRaise
        case curl
        case triceps
        case row
        case shrug
        case squat
        case deadlift
        case rearLunge
        case pushup
    }

    let token: Token
    let stops: [String]
    /// CSS gradient angle in degrees.
    let angle: Double
}

struct WatchItem: Equatable {
    let cueID: CoachingCueID
    let text: String
}

/// Static, non-diagnostic information shown on an exercise's Library and detail cards.
struct ExercisePresentation: Equatable {
    let shortName: String
    let muscles: [String]
    let filterGroups: Set<ExerciseFilterGroup>
    let gradient: ExerciseGradient
    let symbolName: String
    let equipmentLine: String
    let cameraSetupLine: String
    let watchesFor: [WatchItem]
}
