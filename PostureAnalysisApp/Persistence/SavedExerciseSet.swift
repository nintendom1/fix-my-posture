import Foundation
import SwiftData

/// One occurrence in a Saved Set. It has its own id because the same exercise can appear more than once.
struct SavedExerciseSetItem: Codable, Hashable, Identifiable {
    var id = UUID()
    /// Stored by stable id, not display name, so renaming an exercise never breaks a Saved Set.
    var exerciseID: ExerciseID
    var setCount: Int
    var targetRepMinimum: Int
    var targetRepMaximum: Int

    init(id: UUID = UUID(), exerciseID: ExerciseID, setCount: Int, targetRepMinimum: Int, targetRepMaximum: Int) {
        self.id = id
        self.exerciseID = exerciseID
        self.setCount = max(1, setCount)
        self.targetRepMinimum = max(1, targetRepMinimum)
        self.targetRepMaximum = max(self.targetRepMinimum, targetRepMaximum)
    }

    /// A new occurrence using the exercise's current sets and reps.
    init(exercise: ExerciseDefinition) {
        self.init(exerciseID: exercise.id, setCount: exercise.sets, targetRepMinimum: exercise.targetReps.lowerBound,
                  targetRepMaximum: exercise.targetReps.upperBound)
    }

    var targetReps: ClosedRange<Int> { targetRepMinimum...max(targetRepMinimum, targetRepMaximum) }

    var setsAndRepsLabel: String {
        let reps = targetRepMinimum == targetRepMaximum ? "\(targetRepMaximum)" : "\(targetRepMinimum)–\(targetRepMaximum)"
        return "\(setCount) × \(reps)"
    }
}

/// An ordered sequence of exercises with their own sets and reps.
struct SavedExerciseSet: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var items: [SavedExerciseSetItem]

    /// Occurrences whose exercise isn't in the catalog any more; the set shows as needing attention.
    func missingItems(in catalog: [ExerciseDefinition]) -> [SavedExerciseSetItem] {
        items.filter { item in !catalog.contains { $0.id == item.exerciseID } }
    }

    func plan(in catalog: [ExerciseDefinition]) -> WorkoutPlan {
        WorkoutPlan(id: id, name: name, items: items.compactMap { item in
            guard catalog.contains(where: { $0.id == item.exerciseID }) else { return nil }
            return WorkoutPlanItem(id: item.id, exerciseID: item.exerciseID, sets: item.setCount, targetReps: item.targetReps)
        })
    }

    /// A copy with fresh ids, named "<name> Copy".
    func duplicated() -> SavedExerciseSet {
        SavedExerciseSet(name: "\(name) Copy", items: items.map {
            SavedExerciseSetItem(exerciseID: $0.exerciseID, setCount: $0.setCount, targetRepMinimum: $0.targetRepMinimum,
                                 targetRepMaximum: $0.targetRepMaximum)
        })
    }
}

/// Sets and reps the user chose for an exercise on the list, remembered on this phone. The exercise's
/// built-in definition is never changed.
struct ExerciseTarget: Codable, Equatable {
    var sets: Int
    var repMinimum: Int
    var repMaximum: Int

    init(sets: Int, repMinimum: Int, repMaximum: Int) {
        self.sets = max(1, sets)
        self.repMinimum = max(1, repMinimum)
        self.repMaximum = max(self.repMinimum, repMaximum)
    }

    init(_ exercise: ExerciseDefinition) {
        self.init(sets: exercise.sets, repMinimum: exercise.targetReps.lowerBound, repMaximum: exercise.targetReps.upperBound)
    }
}

enum ExerciseTargetStore {
    static func target(for id: ExerciseID, preferences: any AppPreferencesStoring) -> ExerciseTarget? {
        preferences.exerciseTarget(for: id.rawValue)
    }

    /// Nil resets the exercise to its default.
    static func setTarget(_ target: ExerciseTarget?, for id: ExerciseID, preferences: any AppPreferencesStoring) {
        preferences.setExerciseTarget(target, for: id.rawValue)
    }

    /// The catalog with each remembered target applied.
    static func applying(to exercises: [ExerciseDefinition], preferences: any AppPreferencesStoring) -> [ExerciseDefinition] {
        exercises.map { exercise in
            guard let target = target(for: exercise.id, preferences: preferences) else { return exercise }
            return exercise.withTarget(sets: target.sets, reps: target.repMinimum...target.repMaximum)
        }
    }
}
