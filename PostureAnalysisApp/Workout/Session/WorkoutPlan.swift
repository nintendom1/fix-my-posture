import Foundation

/// One occurrence of an exercise in a workout, with its own sets and reps. The same exercise can appear
/// more than once, so each occurrence has its own id.
struct WorkoutPlanItem: Equatable, Identifiable {
    let id: UUID
    let exerciseID: ExerciseID
    var sets: Int
    var targetReps: ClosedRange<Int>
    /// Runs the exercise's smaller-range variant, so a shallow floor and its full-range sample can share one exercise
    /// id in one plan.
    var reducedRange = false
    /// An offer the user may decline, such as Today's Session harder sample.
    var isOptional = false
    /// The extra set the user took after rating an item Easy. It is inserted into the plan while the workout runs,
    /// runs the same exercise and variant, and is never part of what was prescribed.
    var isBonus = false

    /// The exercise this occurrence runs, before its sets and reps apply.
    func resolved(from base: ExerciseDefinition) -> ExerciseDefinition {
        reducedRange ? (base.reducedRange?() ?? base) : base
    }

    /// Starts the label of an optional occurrence.
    static let optionalPrefix = "Optional: "
    /// Starts the label of a bonus occurrence.
    static let bonusPrefix = "Bonus: "

    /// The name a plan shows for this occurrence: the variant it runs, with "Optional: " for an optional one and
    /// "Bonus: " for a bonus.
    func label(for exercise: ExerciseDefinition?) -> String {
        let name = exercise.map { resolved(from: $0).displayName } ?? "Unavailable exercise"
        if isBonus { return Self.bonusPrefix + name }
        return isOptional ? Self.optionalPrefix + name : name
    }
}

/// A request to run one more set of a finished plan item, for the reducer to insert right after it.
struct BonusRequest: Equatable {
    /// The id of the new bonus occurrence.
    let itemID: UUID
    /// The finished occurrence the bonus follows.
    let after: UUID
    /// Reps, or seconds for a timed hold.
    let amount: Int
}

extension ExerciseDefinition {
    /// True for a smaller-range variant made by another definition's `reducedRange` (a shallow wall push-up), which
    /// shares its exercise id with the full-range one. Recordings mark it so replay runs the same variant.
    var isReducedRangeVariant: Bool {
        reducedRange == nil && ExerciseCatalog.definition(for: id)?.reducedRange != nil
    }
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

    /// "2 sets × 8–10 reps", with the limb for one-side-at-a-time exercises.
    var setsAndRepsLabel: String {
        "\(sets) \(sets == 1 ? "set" : "sets") × \(targetAmountLabel)"
            + (perSide ? " each \(sideLimb.rawValue)" : "")
    }
}
