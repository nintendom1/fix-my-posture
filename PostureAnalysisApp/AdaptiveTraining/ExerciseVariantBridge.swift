import AdaptiveTraining
import Foundation

/// Connects the adaptive-training ladders, which name exercises only by stable strings, to the app's
/// exercise catalog. The package never sees `ExerciseDefinition`; this bridge is the one place that maps a rung
/// to an exercise the coach can run and tells the engine which rungs the app can offer.
struct ExerciseVariantBridge {
    let exercises: any ExerciseCatalogProviding
    let ladders: ProgressionCatalog

    init(exercises: any ExerciseCatalogProviding = LiveExerciseCatalog(), ladders: ProgressionCatalog = .v1) {
        self.exercises = exercises
        self.ladders = ladders
    }

    /// Exercise IDs the V1 ladders use that the app hasn't built yet. Each exercise PR removes its ID; a test
    /// fails if an ID is listed here after the exercise lands, or if a ladder names an ID that is in neither place.
    static let notYetBuilt: Set<String> = [
        "sit_to_stand", "scapular_squeeze", "wall_slide", "hip_hinge",
        "glute_squeeze", "weight_shift", "chin_tuck", "abdominal_brace"
    ]

    /// What the engine may prescribe on this device: every exercise in the catalog, limited by the user's equipment.
    func availability(equipment: Set<TrainingEquipment>) -> Availability {
        Availability(builtExerciseIDs: Set(exercises.all.map(\.id.rawValue)), equipment: equipment)
    }

    /// The coach's exercise for a rung, or nil when the app hasn't built it.
    func exercise(for rung: ProgressionRung) -> ExerciseDefinition? {
        guard let exercise = exercises.exercise(ExerciseID(rawValue: rung.exerciseID)) else { return nil }
        guard rung.modifiers.contains(.reducedRange) else { return exercise }
        return exercise.reducedRange?()
    }

    /// The ladder equipment that an exercise's catalog equipment corresponds to.
    static func trainingEquipment(for equipment: ExerciseEquipment) -> [TrainingEquipment] {
        switch equipment {
        case .dumbbells: return [.dumbbells]
        case .band: return [.band]
        case .bodyweight: return []
        }
    }
}
