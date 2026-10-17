import SwiftUI
@testable import PostureAnalysisApp

enum RoutinesFixtures {
    static let design = RoutinesState(routines: [
        RoutineCardPresentation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000321")!,
            name: "Upper Body",
            summary: "4 exercises · 8 sets",
            exerciseNames: ["Shoulder Press", "Dumbbell Row", "Hammer Curl", "Triceps Ext."],
            theme: .exercise(gradient(for: .shoulderPress)),
            canStart: true
        ),
        RoutineCardPresentation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000322")!,
            name: "Quick Strength",
            summary: "3 exercises · 6 sets",
            exerciseNames: ["Air Squat", "Push-Up", "Shoulder Press"],
            theme: .exercise(gradient(for: .airSquat)),
            canStart: true
        ),
        RoutineCardPresentation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000323")!,
            name: "Legs & Push",
            summary: "2 exercises · 6 sets",
            exerciseNames: ["Air Squat", "Push-Up"],
            theme: .exercise(gradient(for: .airSquat)),
            canStart: true
        )
    ])

    static var designTabView: some View {
        TabView(selection: .constant(AppTab.routines)) {
            NavigationStack { Color.clear }
                .tabItem { Label(AppTab.train.title, systemImage: "dumbbell.fill") }
                .tag(AppTab.train)

            NavigationStack {
                ZStack {
                    AuraBackground(tab: .routines)
                    RoutinesScreen(state: design, send: { _ in })
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

    private static func gradient(for id: ExerciseID) -> ExerciseGradient {
        ExerciseCatalog.definition(for: id)!.presentation.gradient
    }
}

enum RoutineDetailFixtures {
    private static let routineID = UUID(uuidString: "00000000-0000-0000-0000-000000000321")!

    static let design = RoutineDetailState(
        routine: RoutineDetailPresentation(
            id: routineID,
            name: "Upper Body",
            summary: "4 exercises · 8 sets",
            steps: [
                step(1, .shoulderPress, target: "2 × 8–10", weight: "20 lb", camera: "Front camera"),
                step(2, .dumbbellRow, target: "2 × 8–10 / side", weight: "25 lb", camera: "Side camera"),
                step(3, .hammerCurl, target: "2 × 8–10", weight: "15 lb", camera: "Front camera"),
                step(4, .tricepsExtension, target: "2 × 10", weight: "15 lb", camera: "Front camera")
            ],
            canStart: true
        ),
        showsDeleteConfirmation: false
    )

    static var designTabView: some View {
        TabView(selection: .constant(AppTab.routines)) {
            NavigationStack { Color.clear }
                .tabItem { Label(AppTab.train.title, systemImage: "dumbbell.fill") }
                .tag(AppTab.train)

            NavigationStack {
                ZStack {
                    AuraBackground(tab: .routines)
                    RoutineDetailScreen(state: design, send: { _ in })
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

    private static func step(
        _ number: Int,
        _ exerciseID: ExerciseID,
        target: String,
        weight: String?,
        camera: String
    ) -> RoutineStepPresentation {
        let exercise = ExerciseCatalog.definition(for: exerciseID)!
        return RoutineStepPresentation(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000033\(number)")!,
            number: number,
            exerciseID: exerciseID,
            name: exercise.presentation.shortName,
            target: target,
            weight: weight,
            camera: camera,
            gradient: exercise.presentation.gradient
        )
    }
}

@MainActor
final class RoutinesTestRepository: RoutineRepository {
    private(set) var sets: [SavedExerciseSet]
    private var createdAt: [UUID: Date]
    private(set) var duplicateInputs: [UUID] = []

    init(sets: [SavedExerciseSet], createdAt: [UUID: Date] = [:]) {
        self.sets = sets
        self.createdAt = createdAt
    }

    func list() throws -> [SavedExerciseSet] {
        sets.enumerated().sorted { lhs, rhs in
            let lhsDate = createdAt[lhs.element.id] ?? .distantPast
            let rhsDate = createdAt[rhs.element.id] ?? .distantPast
            if lhsDate == rhsDate { return lhs.offset < rhs.offset }
            return lhsDate < rhsDate
        }.map(\.element)
    }

    func listWithUpdateDates() throws -> [SavedExerciseSetRecord] {
        sets.map { SavedExerciseSetRecord(set: $0, updatedAt: createdAt[$0.id] ?? .distantPast) }
    }

    func save(_ set: SavedExerciseSet) throws {
        sets.removeAll { $0.id == set.id }
        sets.append(set)
        createdAt[set.id] = Date(timeIntervalSince1970: 100)
    }

    func duplicate(_ set: SavedExerciseSet) throws -> SavedExerciseSet {
        duplicateInputs.append(set.id)
        let copy = set.duplicated()
        try save(copy)
        return copy
    }

    func delete(id: UUID) throws {
        sets.removeAll { $0.id == id }
        createdAt[id] = nil
    }
}

@MainActor
final class RoutinesTestWorkoutHistoryRepository: WorkoutHistoryRepository {
    private(set) var records: [WorkoutRecord]

    init(records: [WorkoutRecord] = []) {
        self.records = records
    }

    func list() throws -> [WorkoutRecord] { records }
    func save(_ record: WorkoutRecord) throws {}
    func updateWeights(for record: WorkoutRecord) throws {}
    func delete(id: UUID) throws {}
}
