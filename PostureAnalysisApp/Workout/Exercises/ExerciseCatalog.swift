import Foundation

protocol ExerciseCatalogProviding {
    var all: [ExerciseDefinition] { get }
    func exercise(_ id: ExerciseID) -> ExerciseDefinition?
}

struct LiveExerciseCatalog: ExerciseCatalogProviding {
    var all: [ExerciseDefinition] { ExerciseCatalog.all }

    func exercise(_ id: ExerciseID) -> ExerciseDefinition? {
        ExerciseCatalog.definition(for: id)
    }
}

/// The exercises the coach offers, in menu order.
enum ExerciseCatalog {
    static let all: [ExerciseDefinition] = [
        ShoulderPressExercise.definition(),
        LateralRaiseExercise.definition(),
        HammerCurlExercise.definition(),
        TricepsExtensionExercise.definition(),
        AirSquatExercise.definition(),
        StiffLegDeadliftExercise.definition(),
        RearLungeExercise.definition(),
        GluteBridgeExercise.definition(),
        DumbbellRowExercise.definition(),
        DumbbellShrugExercise.definition(),
        PushUpExercise.definition()
    ]

    static func definition(for id: ExerciseID) -> ExerciseDefinition? {
        all.first { $0.id == id }
    }
}
