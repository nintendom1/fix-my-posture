import Foundation

/// How the coach knows a set is done.
enum ExerciseTracking: Equatable {
    /// The camera follows the body and counts reps (or the hold) itself.
    case camera
    /// No analyzer: the camera can't follow this movement, so the user says when the set is done, or a hold timer
    /// ends it. The coach never waits for framing and never counts.
    case selfReported
}

/// What one set is measured in.
enum ExerciseDoseUnit: Equatable {
    case reps
    /// A timed hold. For these exercises `targetReps` and `autoCompleteReps` hold seconds, so plans, Saved Sets, and
    /// targets keep one shape.
    case seconds
}

/// The analyzer for self-reported exercises: it never counts and never judges form.
final class SelfReportedAnalyzer: ExerciseAnalyzing {
    let epoch: Int

    init(epoch: Int) {
        self.epoch = epoch
    }

    func process(_ frame: PoseFrame, counting: Bool) -> ExerciseAnalysis {
        ExerciseAnalysis()
    }
}
