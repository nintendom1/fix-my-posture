import SwiftUI
@testable import PostureAnalysisApp

enum ExerciseDetailFixtures {
    private static let exercise = ExerciseCatalog.definition(for: .shoulderPress)!

    static let design = ExerciseDetailState(
        id: exercise.id,
        name: exercise.displayName,
        muscles: exercise.presentation.muscles.joined(separator: " · "),
        gradient: exercise.presentation.gradient,
        symbolName: exercise.presentation.symbolName,
        equipmentText: exercise.presentation.equipmentLine,
        cameraSetupText: exercise.presentation.cameraSetupLine,
        watchesFor: exercise.presentation.watchesFor.map(\.text),
        steps: exercise.guide.steps,
        sets: exercise.sets,
        repMinimum: exercise.targetReps.lowerBound,
        repMaximum: exercise.targetReps.upperBound
    )

    @MainActor
    static var designTabView: some View {
        TabView(selection: .constant(AppTab.train)) {
            NavigationStack {
                ZStack {
                    AuraBackground(tab: .train)
                    ExerciseDetailScreen(state: design, send: { _ in })
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
        .environment(\.exerciseCatalog, LiveExerciseCatalog())
        .environment(\.preferences, InMemoryPreferences())
        .tint(Color(hex: TabBarStyle.design.tintHex(for: .train)))
    }
}
