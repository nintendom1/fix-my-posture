import Foundation
import SwiftData

/// One finished set in the history: its reps, which arm for one-arm exercises, and the weight used.
struct RecordedSet: Codable, Equatable {
    var reps: Int
    /// "L" or "R" for exercises done one arm at a time.
    var side: String?
    var weight: WorkoutWeight?
}

/// One exercise (or one Saved Set occurrence) in a saved workout.
struct WorkoutRecordEntry: Codable, Equatable, Identifiable {
    enum Outcome: String, Codable {
        case completed
        case skipped
    }

    var id = UUID()
    var exerciseID: ExerciseID
    /// The name when the workout was saved, so history still reads well if the exercise changes.
    var name: String
    var outcome: Outcome?
    var sets: [RecordedSet]
}

/// A saved workout: what was done, when, and with what weights.
struct WorkoutRecord: Codable, Equatable, Identifiable {
    var id = UUID()
    var startedAt: Date
    var endedAt: Date
    var planID: UUID?
    var planName: String?
    var entries: [WorkoutRecordEntry]

    var totalReps: Int { entries.flatMap(\.sets).map(\.reps).reduce(0, +) }

    /// Everything the session recorded, or nil when nothing was done. A Saved Set is recorded by occurrence;
    /// otherwise by exercise, with every round included.
    init?(session: WorkoutSession, startedAt: Date, endedAt: Date) {
        func sets(_ reps: [Int], _ weights: [WorkoutWeight?], for exercise: ExerciseDefinition?) -> [RecordedSet] {
            reps.enumerated().map { index, count in
                RecordedSet(reps: count, side: exercise?.perSide == true ? (index % 2 == 0 ? "L" : "R") : nil,
                            weight: weights.indices.contains(index) ? weights[index] : nil)
            }
        }
        var entries: [WorkoutRecordEntry] = []
        if let plan = session.plan {
            for item in plan.items {
                guard let record = session.planRecords[item.id] else { continue }
                let exercise = session.exercises.first { $0.id == item.exerciseID }
                guard !record.setReps.isEmpty || record.outcome != nil else { continue }
                let outcome: WorkoutRecordEntry.Outcome? = record.outcome.map { $0 == .completed ? .completed : .skipped }
                entries.append(WorkoutRecordEntry(exerciseID: item.exerciseID, name: exercise?.displayName ?? item.exerciseID.rawValue,
                                                  outcome: outcome, sets: sets(record.setReps, record.setWeights, for: exercise)))
            }
        } else {
            for exercise in session.exercises {
                guard let progress = session.progress[exercise.id], !progress.setReps.isEmpty else { continue }
                entries.append(WorkoutRecordEntry(exerciseID: exercise.id, name: exercise.displayName, outcome: nil,
                                                  sets: sets(progress.setReps, progress.setWeights, for: exercise)))
            }
        }
        guard entries.contains(where: { !$0.sets.isEmpty }) else { return nil }
        self.init(startedAt: startedAt, endedAt: endedAt, planID: session.plan?.id,
                  planName: session.plan?.name, entries: entries)
    }

    init(id: UUID = UUID(), startedAt: Date, endedAt: Date, planID: UUID? = nil,
         planName: String?, entries: [WorkoutRecordEntry]) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.planID = planID
        self.planName = planName
        self.entries = entries
    }
}
