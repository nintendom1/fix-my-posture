import Foundation

/// The exercises the coach offers, in menu order.
enum ExerciseCatalog {
    static let all: [ExerciseDefinition] = [
        ShoulderPressExercise.definition()
    ]

    static func definition(for id: ExerciseID) -> ExerciseDefinition? {
        all.first { $0.id == id }
    }
}
