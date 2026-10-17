import SwiftUI
@testable import PostureAnalysisApp

enum LibraryFixtures {
    static let design = LibraryState(groups: [
        LibraryExerciseGroup(title: "Upper body", exercises: [
            row(.shoulderPress, target: "2 × 8–10", weight: "20 lb"),
            row(.hammerCurl, target: "2 × 10", weight: nil),
            row(.tricepsExtension, target: "2 × 10", weight: nil),
            row(.dumbbellRow, target: "2 × 8–10 / side", weight: nil),
            row(.pushUp, target: "2 × 10", weight: nil)
        ]),
        LibraryExerciseGroup(title: "Lower body", exercises: [
            row(.airSquat, target: "2 × 15", weight: nil)
        ])
    ])

    @MainActor
    static var designTabView: some View {
        TabView(selection: .constant(AppTab.train)) {
            NavigationStack {
                ZStack {
                    AuraBackground(tab: .train)
                    LibraryScreen(state: design, send: { _ in })
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

    private static func row(_ id: ExerciseID, target: String, weight: String?) -> LibraryExerciseRow {
        let exercise = ExerciseCatalog.definition(for: id)!
        return LibraryExerciseRow(
            id: id,
            name: libraryName(for: id),
            muscles: exercise.presentation.muscles.joined(separator: " · "),
            target: target,
            weight: weight,
            equipment: exercise.presentation.equipmentLine,
            cameraSetup: exercise.presentation.cameraSetupLine,
            gradient: exercise.presentation.gradient,
            symbolName: exercise.presentation.symbolName
        )
    }

    private static func libraryName(for id: ExerciseID) -> String {
        switch id {
        case .tricepsExtension: return "Triceps Extension"
        case .dumbbellRow: return "Dumbbell Row"
        default: return ExerciseCatalog.definition(for: id)!.displayName
        }
    }
}
