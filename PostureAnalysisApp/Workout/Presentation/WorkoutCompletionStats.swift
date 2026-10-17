import Foundation

/// Presentation totals derived from the saved history record, so the completion screen and History
/// show the same set, rep, and weight data.
struct WorkoutCompletionStats: Equatable {
    struct Metric: Equatable, Identifiable {
        let title: String
        let value: String

        var id: String { title }
    }

    struct ExerciseRow: Equatable, Identifiable {
        let id: UUID
        let name: String
        let setCount: Int
        let reps: Int
        let weightLabel: String?
        let outcome: WorkoutRecordEntry.Outcome?

        var summary: String {
            if outcome == .skipped, setCount == 0 {
                return "\(name) — Skipped"
            }

            var details = ["\(setCount) \(setCount == 1 ? "set" : "sets")",
                           "\(reps) \(reps == 1 ? "rep" : "reps")"]
            if let weightLabel { details.append(weightLabel) }
            if outcome == .skipped { details.append("Skipped") }
            return "\(name) — " + details.joined(separator: " · ")
        }
    }

    let exerciseCount: Int
    let totalSets: Int
    let totalReps: Int
    let durationLabel: String
    let exerciseRows: [ExerciseRow]

    var metrics: [Metric] {
        [
            Metric(title: "Exercises", value: String(exerciseCount)),
            Metric(title: "Sets", value: String(totalSets)),
            Metric(title: "Reps", value: String(totalReps)),
            Metric(title: "Time", value: durationLabel)
        ]
    }

    init(record: WorkoutRecord) {
        exerciseCount = record.entries.count
        totalSets = record.entries.reduce(0) { $0 + $1.sets.count }
        totalReps = record.totalReps
        durationLabel = Self.durationLabel(from: record.startedAt, to: record.endedAt)
        exerciseRows = record.entries.map { entry in
            let isOneArm = entry.sets.contains { $0.side != nil }
            let latestWeight = entry.sets.reversed().compactMap(\.weight).first?.label
            let weightLabel = latestWeight.map { isOneArm ? "\($0) / side" : $0 }
            return ExerciseRow(id: entry.id,
                               name: entry.name,
                               setCount: entry.sets.count,
                               reps: entry.sets.reduce(0) { $0 + $1.reps },
                               weightLabel: weightLabel,
                               outcome: entry.outcome)
        }
    }

    private static func durationLabel(from start: Date, to end: Date) -> String {
        let seconds = max(0, end.timeIntervalSince(start))
        guard seconds >= 60 else { return "<1m" }
        return "\(max(1, Int((seconds / 60).rounded())))m"
    }
}
