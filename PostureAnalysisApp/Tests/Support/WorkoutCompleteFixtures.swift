import SwiftUI
@testable import PostureAnalysisApp

enum WorkoutCompleteFixtures {
    static let ids: Set<String> = ["complete"]

    @MainActor
    static func screen() -> some View {
        WorkoutCompleteScreen(
            viewModel: WorkoutCompleteViewModel(record: record, router: nil),
            onDone: {}
        )
    }

    static let record = WorkoutRecord(
        startedAt: Date(timeIntervalSince1970: 100),
        endedAt: Date(timeIntervalSince1970: 100 + 26 * 60),
        planName: "Upper Body",
        entries: [
            entry(.shoulderPress, "Shoulder Press", reps: [10, 9], weights: [.mass(20, .pounds), .mass(20, .pounds)]),
            entry(.hammerCurl, "Hammer Curl", reps: [10, 10], weights: [.mass(15, .pounds), .mass(17.5, .pounds)]),
            entry(.dumbbellRow, "Dumbbell Row", reps: [8, 8, 8, 8], sides: ["L", "R", "L", "R"],
                  weights: [.mass(20, .pounds), .mass(20, .pounds), .mass(20, .pounds), .mass(20, .pounds)]),
            entry(.airSquat, "Air Squat", reps: [12, 11])
        ]
    )

    private static func entry(
        _ id: ExerciseID,
        _ name: String,
        reps: [Int],
        sides: [String]? = nil,
        weights: [WorkoutWeight?] = []
    ) -> WorkoutRecordEntry {
        WorkoutRecordEntry(
            exerciseID: id,
            name: name,
            outcome: nil,
            sets: reps.enumerated().map { index, count in
                RecordedSet(reps: count,
                            side: sides?.indices.contains(index) == true ? sides?[index] : nil,
                            weight: weights.indices.contains(index) ? weights[index] : nil)
            }
        )
    }
}
