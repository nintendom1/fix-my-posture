import Foundation

/// A deliberately small, predictable estimate for the time needed to complete a Saved Set.
enum RoutineEstimator {
    private static let setupSeconds = 60.0
    private static let frameTransitionSeconds = 15.0
    private static let secondsPerRep = 4.0
    private static let sideSwitchSeconds = 10.0

    /// Estimates setup, movement time, side changes, rests, and framing between known exercises.
    /// Unknown exercises are skipped; an empty or wholly unavailable routine takes zero seconds.
    static func seconds(
        for routine: SavedExerciseSet,
        exercises: [ExerciseDefinition],
        restPolicy: RestPolicy
    ) -> Double {
        let knownItems = routine.items.compactMap { item -> (SavedExerciseSetItem, ExerciseDefinition)? in
            guard let exercise = exercises.first(where: { $0.id == item.exerciseID }) else { return nil }
            return (item, exercise)
        }
        guard !knownItems.isEmpty else { return 0 }

        var totalSeconds = setupSeconds
        for (index, pair) in knownItems.enumerated() {
            let (item, exercise) = pair
            let midpointReps = Double(item.targetReps.lowerBound + item.targetReps.upperBound) / 2
            let sideMultiplier = exercise.perSide ? 2.0 : 1.0
            let setCount = max(1, item.setCount)
            let restSeconds = restSeconds(for: exercise, policy: restPolicy)
            totalSeconds += Double(setCount) * midpointReps * sideMultiplier * secondsPerRep
            if exercise.perSide {
                totalSeconds += Double(setCount) * sideSwitchSeconds
            }
            totalSeconds += Double(max(0, setCount - 1)) * restSeconds

            if index < knownItems.count - 1 {
                totalSeconds += restSeconds + frameTransitionSeconds
            }
        }
        return totalSeconds
    }

    static func minutes(
        for routine: SavedExerciseSet,
        exercises: [ExerciseDefinition],
        restPolicy: RestPolicy
    ) -> Int {
        Int((seconds(for: routine, exercises: exercises, restPolicy: restPolicy) / 60).rounded())
    }

    private static func restSeconds(for exercise: ExerciseDefinition, policy: RestPolicy) -> Double {
        switch policy {
        case .exerciseDefault:
            return Double(exercise.restSeconds)
        case .fixed(let seconds):
            return Double(min(max(seconds, 30), 120))
        }
    }
}
