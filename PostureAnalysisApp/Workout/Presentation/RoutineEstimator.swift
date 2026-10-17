import Foundation

/// A deliberately small, predictable estimate for the time needed to complete a Saved Set.
enum RoutineEstimator {
    private static let secondsPerRep = 6.0
    private static let setupSeconds = 130.0
    private static let transitionSeconds = 40.0

    static func minutes(
        for routine: SavedExerciseSet,
        exercises: [ExerciseDefinition],
        restPolicy: RestPolicy
    ) -> Int {
        let knownItems = routine.items.compactMap { item -> (SavedExerciseSetItem, ExerciseDefinition)? in
            guard let exercise = exercises.first(where: { $0.id == item.exerciseID }) else { return nil }
            return (item, exercise)
        }
        guard !knownItems.isEmpty else { return 0 }

        let totalSeconds = knownItems.reduce(0.0) { total, pair in
            let (item, exercise) = pair
            let midpointReps = Double(item.targetReps.lowerBound + item.targetReps.upperBound) / 2
            let reps = midpointReps * (exercise.perSide ? 2 : 1)
            let work = Double(item.setCount) * reps * secondsPerRep
            let restSeconds: Int
            switch restPolicy {
            case .exerciseDefault:
                restSeconds = exercise.restSeconds
            case .fixed(let seconds):
                restSeconds = seconds
            }
            let rest = Double(max(0, item.setCount - 1) * max(0, restSeconds))
            return total + work + rest + setupSeconds
        } + Double(max(0, knownItems.count - 1)) * transitionSeconds

        return Int((totalSeconds / 60).rounded())
    }
}
