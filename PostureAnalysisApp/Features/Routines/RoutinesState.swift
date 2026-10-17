import Foundation

enum RoutineTheme: Equatable {
    case exercise(ExerciseGradient)
    case brand
}

struct RoutineCardPresentation: Equatable, Identifiable {
    let id: UUID
    let name: String
    let summary: String
    let exerciseNames: [String]
    let theme: RoutineTheme
    let canStart: Bool
}

struct RoutinesState: Equatable {
    var routines: [RoutineCardPresentation]
    var deleteConfirmationRoutineID: UUID?

    init(routines: [RoutineCardPresentation], deleteConfirmationRoutineID: UUID? = nil) {
        self.routines = routines
        self.deleteConfirmationRoutineID = deleteConfirmationRoutineID
    }

    var showsDeleteConfirmation: Bool { deleteConfirmationRoutineID != nil }
}

enum RoutinesIntent: Equatable {
    case appeared
    case open(UUID)
    case start(UUID)
    case createRoutine
    case edit(UUID)
    case duplicate(UUID)
    case requestDelete(UUID)
    case confirmDelete
    case cancelDelete
}
