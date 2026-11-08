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
        /// Seconds held across the entry's timed sets; nil when it has none.
        var seconds: Int? = nil
        let weightLabel: String?
        let outcome: WorkoutRecordEntry.Outcome?
        /// Today's Session harder sample, which the user may decline.
        var isOptional = false
        /// The extra set the user took after rating an item Easy. It is never prescribed, so it is never skipped.
        var isBonus = false

        /// "8 reps", or "40 s" for timed holds.
        var amountLabel: String {
            seconds.map { "\($0) s" } ?? "\(reps) \(reps == 1 ? "rep" : "reps")"
        }

        var summary: String {
            if outcome == .skipped, setCount == 0 {
                return "\(name) — \(isOptional ? "Optional, skipped" : "Skipped")"
            }

            var details = ["\(setCount) \(setCount == 1 ? "set" : "sets")", amountLabel]
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
        // A bonus repeats an exercise already counted, though its sets and reps still add up.
        exerciseCount = record.entries.filter { !Self.isBonus($0) }.count
        totalSets = record.entries.reduce(0) { $0 + $1.sets.count }
        totalReps = record.totalReps
        let isTodaySession = AdaptiveTrainingCoordinator.isTodaySession(record)
        durationLabel = isTodaySession
            ? Self.tinyDurationLabel(from: record.startedAt, to: record.endedAt)
            : Self.durationLabel(from: record.startedAt, to: record.endedAt)
        exerciseRows = record.entries.enumerated().map { index, entry in
            let isOneArm = entry.sets.contains { $0.side != nil }
            let latestWeight = entry.sets.reversed().compactMap(\.weight).first?.label
            let weightLabel = latestWeight.map { isOneArm ? "\($0) / side" : $0 }
            let heldSeconds = entry.sets.compactMap(\.seconds)
            // Today's Session lists its main item first; anything after it but a bonus is the optional harder sample.
            // Entries saved from the plan already carry "Optional: "; an older one gets it once.
            let isBonus = Self.isBonus(entry)
            let isOptional = isTodaySession && index > 0 && !isBonus
            let hasPrefix = entry.name.hasPrefix(WorkoutPlanItem.optionalPrefix)
            return ExerciseRow(id: entry.id,
                               name: isOptional && !hasPrefix ? WorkoutPlanItem.optionalPrefix + entry.name : entry.name,
                               setCount: entry.sets.count,
                               reps: entry.sets.reduce(0) { $0 + $1.reps },
                               seconds: heldSeconds.isEmpty ? nil : heldSeconds.reduce(0, +),
                               weightLabel: weightLabel,
                               outcome: entry.outcome,
                               isOptional: isOptional,
                               isBonus: isBonus)
        }
    }

    /// A bonus entry is named "Bonus: <name>" when the workout is saved.
    private static func isBonus(_ entry: WorkoutRecordEntry) -> Bool {
        entry.name.hasPrefix(WorkoutPlanItem.bonusPrefix)
    }

    private static func durationLabel(from start: Date, to end: Date) -> String {
        let seconds = max(0, end.timeIntervalSince(start))
        guard seconds >= 60 else { return "<1m" }
        return "\(max(1, Int((seconds / 60).rounded())))m"
    }

    /// A short Today's Session shows its actual length ("40 s") or "Done", never "<1m".
    private static func tinyDurationLabel(from start: Date, to end: Date) -> String {
        let seconds = max(0, end.timeIntervalSince(start))
        guard seconds < 60 else { return durationLabel(from: start, to: end) }
        return seconds >= 1 ? "\(Int(seconds.rounded(.down))) s" : "Done"
    }
}
