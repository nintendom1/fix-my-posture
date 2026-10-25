import Foundation

struct RoutineStepPresentation: Equatable, Identifiable {
    let id: UUID
    let number: Int
    let exerciseID: ExerciseID
    let name: String
    let target: String
    let weight: String?
    let camera: String
    let gradient: ExerciseGradient

    var targetLine: String {
        guard let weight, !weight.isEmpty else { return target }
        return "\(target) · \(weight)"
    }
}

struct RoutineDetailPresentation: Equatable, Identifiable {
    let id: UUID
    let name: String
    let summary: String
    let lastDoneLabel: String?
    let steps: [RoutineStepPresentation]
    let canStart: Bool
    let isBuiltIn: Bool

    init(
        id: UUID,
        name: String,
        summary: String,
        lastDoneLabel: String?,
        steps: [RoutineStepPresentation],
        canStart: Bool,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.lastDoneLabel = lastDoneLabel
        self.steps = steps
        self.canStart = canStart
        self.isBuiltIn = isBuiltIn
    }

    /// The header's Edit button edits in place, so starter routines don't show it.
    var showsEditButton: Bool { !isBuiltIn }

    /// The action buttons under the steps, in display order.
    var actionButtons: [RoutineAction] {
        isBuiltIn ? [.duplicateToEdit] : [.duplicate, .delete]
    }
}

struct RoutineDetailState: Equatable {
    var routine: RoutineDetailPresentation?
    var showsDeleteConfirmation: Bool

    init(routine: RoutineDetailPresentation?, showsDeleteConfirmation: Bool = false) {
        self.routine = routine
        self.showsDeleteConfirmation = showsDeleteConfirmation
    }

    var isBuiltIn: Bool { routine?.isBuiltIn == true }
}

enum RoutineDetailIntent: Equatable {
    case appeared
    case back
    case edit
    case duplicate
    case requestDelete
    case confirmDelete
    case cancelDelete
    case start
}
