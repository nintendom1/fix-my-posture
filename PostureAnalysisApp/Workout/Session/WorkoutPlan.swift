import Foundation

/// One occurrence of an exercise in a workout, with its own sets and reps. The same exercise can appear
/// more than once, so each occurrence has its own id.
struct WorkoutPlanItem: Equatable, Identifiable {
    let id: UUID
    let exerciseID: ExerciseID
    var sets: Int
    var targetReps: ClosedRange<Int>
}

/// Exercises run one after another, such as a Saved Set.
struct WorkoutPlan: Equatable {
    var id: UUID?
    var name: String
    var items: [WorkoutPlanItem]

    init(id: UUID? = nil, name: String, items: [WorkoutPlanItem]) {
        self.id = id
        self.name = name
        self.items = items
    }
}

/// What happened to one occurrence in a plan.
struct PlanItemRecord: Equatable {
    enum Outcome: Equatable {
        case completed
        case skipped
    }

    var outcome: Outcome?
    /// Reps for each finished set entry of this occurrence.
    var setReps: [Int] = []
    /// The weight used for each of those sets.
    var setWeights: [WorkoutWeight?] = []
}

extension ExerciseDefinition {
    /// The same exercise with a different set count and rep target, for one workout only.
    func withTarget(sets: Int, reps: ClosedRange<Int>) -> ExerciseDefinition {
        var copy = self
        copy.sets = max(1, sets)
        copy.targetReps = reps
        copy.autoCompleteReps = reps.upperBound
        copy.targetRangeAnnouncementReps = reps.lowerBound < reps.upperBound ? reps.lowerBound : nil
        return copy
    }

    /// "2 sets × 8–10 reps", with "each arm" for one-arm-at-a-time exercises.
    var setsAndRepsLabel: String {
        "\(sets) \(sets == 1 ? "set" : "sets") × \(targetLabel) reps" + (perSide ? " each arm" : "")
    }
}
