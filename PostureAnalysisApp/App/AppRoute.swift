import Foundation

/// Stable destinations used by the tab stacks and full-screen presentations.
enum AppRoute: Codable, Hashable, Identifiable {
    case train
    case routines
    case routine(id: UUID)
    case routineEditor(id: UUID?)
    case library
    case exercise(id: ExerciseID)
    case workout(exerciseID: ExerciseID?, routineID: UUID?)
    case workoutComplete
    case progress
    case history
    case posture
    case postureHistory
    case assessment(id: UUID)
    case livePostureCheck
    case photoAssessment(view: PostureView)
    case settings

    var id: String { String(reflecting: self) }

    var owningTab: AppTab {
        switch self {
        case .train, .library, .exercise, .workout, .workoutComplete, .settings:
            return .train
        case .routines, .routine, .routineEditor:
            return .routines
        case .progress, .history:
            return .progress
        case .posture, .postureHistory, .assessment, .livePostureCheck, .photoAssessment:
            return .posture
        }
    }

    var isPresentedFullScreen: Bool {
        switch self {
        case .settings, .workout:
            return true
        default:
            return false
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case train
    case routines
    case progress
    case posture

    var id: Self { self }

    var title: String {
        switch self {
        case .train: return "Train"
        case .routines: return "Routines"
        case .progress: return "Progress"
        case .posture: return "Posture"
        }
    }

    var materialIcon: String {
        switch self {
        case .train: return "fitness_center"
        case .routines: return "format_list_numbered"
        case .progress: return "monitoring"
        case .posture: return "accessibility_new"
        }
    }
}
