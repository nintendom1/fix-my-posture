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
    let steps: [RoutineStepPresentation]
    let canStart: Bool
}

struct RoutineDetailState: Equatable {
    var routine: RoutineDetailPresentation?
    var showsDeleteConfirmation: Bool

    init(routine: RoutineDetailPresentation?, showsDeleteConfirmation: Bool = false) {
        self.routine = routine
        self.showsDeleteConfirmation = showsDeleteConfirmation
    }
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
