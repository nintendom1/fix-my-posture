import Foundation

enum RoutineTheme: Equatable {
    case exercise(ExerciseGradient)
    case brand
}

/// An action a routine card or detail screen offers. Starter routines only offer a copy to edit.
enum RoutineAction: Hashable {
    case edit
    case duplicate
    case duplicateToEdit
    case delete

    var title: String {
        switch self {
        case .edit: return "Edit"
        case .duplicate: return "Duplicate"
        case .duplicateToEdit: return "Duplicate to Edit"
        case .delete: return "Delete"
        }
    }
}

struct RoutineCardPresentation: Equatable, Identifiable {
    let id: UUID
    let name: String
    let summary: String
    let lastDoneLabel: String?
    let exerciseNames: [String]
    let theme: RoutineTheme
    let canStart: Bool
    let isBuiltIn: Bool

    init(
        id: UUID,
        name: String,
        summary: String,
        lastDoneLabel: String?,
        exerciseNames: [String],
        theme: RoutineTheme,
        canStart: Bool,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.lastDoneLabel = lastDoneLabel
        self.exerciseNames = exerciseNames
        self.theme = theme
        self.canStart = canStart
        self.isBuiltIn = isBuiltIn
    }

    /// The card's actions menu, in display order.
    var menuActions: [RoutineAction] {
        isBuiltIn ? [.duplicateToEdit] : [.edit, .duplicate, .delete]
    }
}

struct RoutinesState: Equatable {
    var routines: [RoutineCardPresentation]
    var starterRoutines: [RoutineCardPresentation]
    var deleteConfirmationRoutineID: UUID?

    init(
        routines: [RoutineCardPresentation],
        starterRoutines: [RoutineCardPresentation] = [],
        deleteConfirmationRoutineID: UUID? = nil
    ) {
        self.routines = routines
        self.starterRoutines = starterRoutines
        self.deleteConfirmationRoutineID = deleteConfirmationRoutineID
    }

    var allRoutines: [RoutineCardPresentation] { routines + starterRoutines }
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
