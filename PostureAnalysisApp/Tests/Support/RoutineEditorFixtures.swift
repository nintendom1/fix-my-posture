import SwiftUI
@testable import PostureAnalysisApp

enum RoutineEditorFixtures {
    private static let catalog = LiveExerciseCatalog()
    private static let routineID = UUID(uuidString: "00000000-0000-0000-0000-000000000303")!

    static let editState = RoutineEditorState(
        name: "Upper Body",
        items: [
            item("00000000-0000-0000-0000-000000000311", .shoulderPress, sets: 3, min: 8, max: 10, expanded: true),
            item("00000000-0000-0000-0000-000000000312", .dumbbellRow, sets: 3, min: 8, max: 10),
            item("00000000-0000-0000-0000-000000000313", .hammerCurl, sets: 2, min: 10, max: 10),
            item("00000000-0000-0000-0000-000000000314", .tricepsExtension, sets: 2, min: 10, max: 10)
        ],
        isNew: false,
        estimatedMinutes: 30
    )

    static let newState = RoutineEditorState(name: "", isNew: true)

    @MainActor
    static var designTabView: some View {
        editorTabView(state: editState)
    }

    @MainActor
    static var newRoutineTabView: some View {
        editorTabView(state: newState)
    }

    @MainActor
    static var pickerSheet: some View {
        TabView(selection: .constant(AppTab.routines)) {
            NavigationStack { Color.clear }
                .tabItem { Label(AppTab.train.title, systemImage: "dumbbell.fill") }
                .tag(AppTab.train)

            NavigationStack {
                ZStack {
                    AuraBackground(tab: .routines)
                    RoutineEditorScreen(state: editState, send: { _ in })
                }
                .toolbar(.hidden, for: .navigationBar)
                .overlay(alignment: .top) {
                    AddExerciseSheet(state: pickerState, send: { _ in })
                        .frame(height: 724)
                        .padding(.top, 66)
                }
            }
            .tabItem { Label(AppTab.routines.title, systemImage: "list.number") }
            .tag(AppTab.routines)

            NavigationStack { Color.clear }
                .tabItem { Label(AppTab.progress.title, systemImage: "chart.xyaxis.line") }
                .tag(AppTab.progress)
            NavigationStack { Color.clear }
                .tabItem { Label(AppTab.posture.title, systemImage: "figure.stand") }
                .tag(AppTab.posture)
        }
        .tint(Color(hex: TabBarStyle.design.tintHex(for: .routines)))
    }

    @MainActor
    private static func editorTabView(state: RoutineEditorState) -> some View {
        TabView(selection: .constant(AppTab.routines)) {
            NavigationStack { Color.clear }
                .tabItem { Label(AppTab.train.title, systemImage: "dumbbell.fill") }
                .tag(AppTab.train)

            NavigationStack {
                ZStack {
                    AuraBackground(tab: .routines)
                    RoutineEditorScreen(state: state, send: { _ in })
                }
                .toolbar(.hidden, for: .navigationBar)
            }
            .tabItem { Label(AppTab.routines.title, systemImage: "list.number") }
            .tag(AppTab.routines)

            NavigationStack { Color.clear }
                .tabItem { Label(AppTab.progress.title, systemImage: "chart.xyaxis.line") }
                .tag(AppTab.progress)
            NavigationStack { Color.clear }
                .tabItem { Label(AppTab.posture.title, systemImage: "figure.stand") }
                .tag(AppTab.posture)
        }
        .tint(Color(hex: TabBarStyle.design.tintHex(for: .routines)))
    }

    private static var pickerState: RoutineEditorState {
        var state = editState
        state.isPickerPresented = true
        let order = ["shoulder_press", "hammer_curl", "triceps_extension", "dumbbell_row", "air_squat", "push_up"]
        let exercises = ExerciseCatalog.all.sorted {
            (order.firstIndex(of: $0.id.rawValue) ?? order.count) < (order.firstIndex(of: $1.id.rawValue) ?? order.count)
        }
        state.pickerExercises = exercises.map { exercise in
            AddExercisePresentation(
                exerciseID: exercise.id,
                name: exercise.presentation.shortName,
                target: "\(exercise.sets) × \(exercise.targetLabel)",
                muscles: exercise.presentation.muscles.joined(separator: " · "),
                gradient: exercise.presentation.gradient,
                symbolName: exercise.presentation.symbolName,
                inRoutineCount: editState.items.filter { $0.exerciseID == exercise.id }.count
            )
        }
        return state
    }

    private static func item(
        _ id: String,
        _ exerciseID: ExerciseID,
        sets: Int,
        min: Int,
        max: Int,
        expanded: Bool = false
    ) -> RoutineEditorItemState {
        let definition = catalog.exercise(exerciseID)!
        return RoutineEditorItemState(
            id: UUID(uuidString: id)!,
            exerciseID: exerciseID,
            name: definition.presentation.shortName,
            gradient: definition.presentation.gradient,
            symbolName: definition.presentation.symbolName,
            isAvailable: true,
            isPerSide: definition.perSide,
            setCount: sets,
            minimumReps: min,
            maximumReps: max,
            isExpanded: expanded
        )
    }
}
