import Foundation

struct WorkoutCompleteState: Equatable {
    let title: String
    let routineName: String
    let subtitle: String
    let stats: WorkoutCompletionStats

    init(record: WorkoutRecord) {
        title = "Workout complete!"
        routineName = record.planName ?? record.entries.first?.name ?? "Workout"
        let hasSkippedExercise = record.entries.contains { $0.outcome == .skipped }
        subtitle = "\(routineName) · \(hasSkippedExercise ? "workout complete" : "every set done")"
        stats = WorkoutCompletionStats(record: record)
    }
}
