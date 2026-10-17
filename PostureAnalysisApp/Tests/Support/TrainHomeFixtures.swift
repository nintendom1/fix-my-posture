import SwiftUI
@testable import PostureAnalysisApp

enum TrainHomeFixtures {
    static let design = TrainHomeState(
        dateLabel: TrainHomeDateFormatter.label(FixedClock.date, timeZone: FixedClock.timeZone),
        heroRoutine: TrainHomeRoutinePresentation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!,
            name: "Upper Body",
            exerciseCount: 4,
            setCount: 8,
            estimatedMinutes: 25,
            chips: ["Shoulder Press", "Row", "Hammer Curl", "+1"],
            canStart: true
        ),
        exercises: [
            tile(.shoulderPress, target: "2 × 8–10"),
            tile(.airSquat, target: "2 × 10–15"),
            tile(.dumbbellRow, target: "2 × 8–10 / side"),
            tile(.pushUp, target: "2 × 8–12")
        ],
        lastWorkout: TrainLastWorkoutPresentation(
            dateLabel: "Last workout · Wed",
            summary: "Upper Body · 26 min · 74 reps"
        )
    )

    static var designTabView: some View {
        TabView(selection: .constant(AppTab.train)) {
            NavigationStack {
                ZStack {
                    AuraBackground(tab: .train)
                    TrainHomeScreen(state: design, send: { _ in })
                }
                .toolbar(.hidden, for: .navigationBar)
            }
            .tabItem { Label(AppTab.train.title, systemImage: "dumbbell.fill") }
            .tag(AppTab.train)

            NavigationStack { Color.clear }
                .tabItem { Label(AppTab.routines.title, systemImage: "list.number") }
                .tag(AppTab.routines)
            NavigationStack { Color.clear }
                .tabItem { Label(AppTab.progress.title, systemImage: "chart.xyaxis.line") }
                .tag(AppTab.progress)
            NavigationStack { Color.clear }
                .tabItem { Label(AppTab.posture.title, systemImage: "figure.stand") }
                .tag(AppTab.posture)
        }
        .tint(Color(hex: TabBarStyle.design.tintHex(for: .train)))
    }

    private static func tile(_ id: ExerciseID, target: String) -> TrainExerciseTile {
        let exercise = ExerciseCatalog.definition(for: id)!
        return TrainExerciseTile(
            id: id,
            name: exercise.presentation.shortName,
            target: target,
            gradient: exercise.presentation.gradient,
            symbolName: exercise.presentation.symbolName
        )
    }
}
