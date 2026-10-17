import SwiftUI
@testable import PostureAnalysisApp

enum ProgressFixtures {
    static let ids: Set<String> = ["progress"]

    @MainActor
    static func designTabView() -> some View {
        TabView(selection: .constant(AppTab.progress)) {
            NavigationStack { Color.clear }
                .tabItem { Label(AppTab.train.title, systemImage: "dumbbell.fill") }
                .tag(AppTab.train)
            NavigationStack { Color.clear }
                .tabItem { Label(AppTab.routines.title, systemImage: "list.number") }
                .tag(AppTab.routines)
            NavigationStack {
                ZStack {
                    AuraBackground(tab: .progress)
                    ProgressScreen(viewModel: ProgressViewModel(
                        workoutHistory: FixtureWorkoutHistoryRepository(records: ProgressHistoryFixtures.records),
                        assessments: FixtureAssessmentRepository(assessments: ProgressHistoryFixtures.assessments),
                        router: nil,
                        now: { FixedClock.date },
                        calendar: FixedClock.calendar
                    ))
                }
                .toolbar(.hidden, for: .navigationBar)
            }
            .tabItem { Label(AppTab.progress.title, systemImage: "chart.xyaxis.line") }
            .tag(AppTab.progress)
            NavigationStack { Color.clear }
                .tabItem { Label(AppTab.posture.title, systemImage: "figure.stand") }
                .tag(AppTab.posture)
        }
        .tint(Color(hex: TabBarStyle.design.tintHex(for: .progress)))
    }
}

enum HistoryFixtures {
    static let ids: Set<String> = ["history"]

    @MainActor
    static func designTabView() -> some View {
        TabView(selection: .constant(AppTab.progress)) {
            NavigationStack { Color.clear }
                .tabItem { Label(AppTab.train.title, systemImage: "dumbbell.fill") }
                .tag(AppTab.train)
            NavigationStack { Color.clear }
                .tabItem { Label(AppTab.routines.title, systemImage: "list.number") }
                .tag(AppTab.routines)
            NavigationStack {
                ZStack {
                    AuraBackground(tab: .progress)
                    HistoryScreen(viewModel: HistoryViewModel(
                        repository: FixtureWorkoutHistoryRepository(records: ProgressHistoryFixtures.records),
                        exerciseCatalog: LiveExerciseCatalog(),
                        now: { FixedClock.date },
                        calendar: FixedClock.calendar
                    ))
                }
                .toolbar(.hidden, for: .navigationBar)
            }
            .tabItem { Label(AppTab.progress.title, systemImage: "chart.xyaxis.line") }
            .tag(AppTab.progress)
            NavigationStack { Color.clear }
                .tabItem { Label(AppTab.posture.title, systemImage: "figure.stand") }
                .tag(AppTab.posture)
        }
        .tint(Color(hex: TabBarStyle.design.tintHex(for: .progress)))
    }
}

enum ProgressHistoryFixtures {
    static let records = [upperBody, quickStrength, lastWeekLegsAndPush, lastWeekUpperBody, lastWeekShoulderPress]

    private static let upperBody = WorkoutRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000371")!,
        startedAt: date(2026, 10, 14, hour: 12),
        endedAt: date(2026, 10, 14, hour: 12).addingTimeInterval(26 * 60),
        planName: "Upper Body",
        entries: [
            entry(.shoulderPress, "Shoulder Press", reps: [10, 9], weights: [.mass(20, .pounds), .mass(20, .pounds)]),
            entry(.dumbbellRow, "Row", reps: [9, 9], weights: [.mass(25, .pounds), .mass(25, .pounds)]),
            entry(.hammerCurl, "Hammer Curl", reps: [10, 10], weights: [.mass(15, .pounds), .mass(15, .pounds)]),
            entry(.tricepsExtension, "Triceps", reps: [9, 8], weights: [.mass(15, .pounds), .mass(15, .pounds)])
        ]
    )

    private static let quickStrength = WorkoutRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000372")!,
        startedAt: date(2026, 10, 12, hour: 17),
        endedAt: date(2026, 10, 12, hour: 17).addingTimeInterval(18 * 60),
        planName: "Quick Strength",
        entries: [
            entry(.airSquat, "Air Squat", reps: [10, 9]),
            entry(.pushUp, "Push-Up", reps: [8, 8]),
            entry(.shoulderPress, "Shoulder Press", reps: [8, 8], weights: [.mass(20, .pounds), .mass(20, .pounds)])
        ]
    )

    private static let lastWeekLegsAndPush = WorkoutRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000373")!,
        startedAt: date(2026, 10, 9, hour: 15),
        endedAt: date(2026, 10, 9, hour: 15).addingTimeInterval(15 * 60),
        planName: "Legs & Push",
        entries: [
            entry(.airSquat, "Air Squat", reps: [12, 12, 12]),
            entry(.pushUp, "Push-Up", reps: [11, 11, 10])
        ]
    )

    private static let lastWeekUpperBody = WorkoutRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000374")!,
        startedAt: date(2026, 10, 7, hour: 15),
        endedAt: date(2026, 10, 7, hour: 15).addingTimeInterval(27 * 60),
        planName: "Upper Body",
        entries: [
            entry(.shoulderPress, "Shoulder Press", reps: [9, 9], weights: [.mass(17.5, .pounds), .mass(17.5, .pounds)]),
            entry(.dumbbellRow, "Row", reps: [9, 9], weights: [.mass(25, .pounds), .mass(25, .pounds)]),
            entry(.hammerCurl, "Hammer Curl", reps: [9, 9], weights: [.mass(15, .pounds), .mass(15, .pounds)]),
            entry(.tricepsExtension, "Triceps", reps: [9, 9], weights: [.mass(15, .pounds), .mass(15, .pounds)])
        ]
    )

    private static let lastWeekShoulderPress = WorkoutRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000375")!,
        startedAt: date(2026, 10, 5, hour: 15),
        endedAt: date(2026, 10, 5, hour: 15).addingTimeInterval(8 * 60),
        planName: nil,
        entries: [entry(.shoulderPress, "Shoulder Press", reps: [9, 9], weights: [.mass(17.5, .pounds), .mass(17.5, .pounds)])]
    )

    static let assessments = [10, 8, 5].map { day in
        PostureAssessment(
            date: date(2026, 10, day, hour: 10),
            imageRelativePath: "fixture-\(day).jpg",
            view: .front,
            pose: BodyPose(landmarks: [:], imageWidth: 390, imageHeight: 844),
            measurements: []
        )
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int) -> Date {
        FixedClock.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static func entry(
        _ exerciseID: ExerciseID,
        _ name: String,
        reps: [Int],
        sides: [String]? = nil,
        weights: [WorkoutWeight?] = []
    ) -> WorkoutRecordEntry {
        WorkoutRecordEntry(
            exerciseID: exerciseID,
            name: name,
            outcome: .completed,
            sets: reps.enumerated().map { index, count in
                RecordedSet(
                    reps: count,
                    side: sides?.indices.contains(index) == true ? sides?[index] : nil,
                    weight: weights.indices.contains(index) ? weights[index] : nil
                )
            }
        )
    }
}

@MainActor
private final class FixtureWorkoutHistoryRepository: WorkoutHistoryRepository {
    private var records: [WorkoutRecord]

    init(records: [WorkoutRecord]) { self.records = records }
    func list() throws -> [WorkoutRecord] { records.sorted { $0.startedAt > $1.startedAt } }
    func save(_ record: WorkoutRecord) throws { records.append(record) }
    func updateWeights(for record: WorkoutRecord) throws {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index] = record
    }
    func delete(id: UUID) throws { records.removeAll { $0.id == id } }
}

@MainActor
private final class FixtureAssessmentRepository: AssessmentRepository {
    private let assessments: [PostureAssessment]

    init(assessments: [PostureAssessment]) { self.assessments = assessments }
    func list() throws -> [PostureAssessment] { assessments }
    func save(_ assessment: PostureAssessment, imageRelativePath: String) throws {}
    func setBaseline(id: UUID, isBaseline: Bool) throws {}
    func delete(id: UUID) throws {}
}
