import XCTest
@testable import PostureAnalysisApp

@MainActor
final class ProgressHistoryViewModelTests: XCTestCase {
    func testProgressViewModelBuildsWeeklyStatsRecentRowsAndPostureSummary() {
        let workouts = MemoryWorkoutHistoryRepository(records: [
            makeRecord(start: date(2026, 10, 14, hour: 10), duration: 26, name: "Upper Body", reps: [10, 9, 10, 10, 9, 9, 9, 8]),
            makeRecord(start: date(2026, 10, 12, hour: 10), duration: 18, name: "Quick Strength", reps: [9, 9, 9, 8, 8, 8])
        ])
        let assessments = MemoryAssessmentRepository(assessments: [
            makeAssessment(date: date(2026, 10, 10, hour: 10)),
            makeAssessment(date: date(2026, 10, 8, hour: 10)),
            makeAssessment(date: date(2026, 10, 5, hour: 10))
        ])

        let viewModel = ProgressViewModel(
            workoutHistory: workouts,
            assessments: assessments,
            router: AppRouter(),
            now: { FixedClock.date },
            calendar: FixedClock.calendar
        )

        XCTAssertEqual(viewModel.state.weeklyStats.workoutCount, 2)
        XCTAssertEqual(viewModel.state.weeklyStats.setCount, 14)
        XCTAssertEqual(viewModel.state.weeklyStats.repCount, 125)
        XCTAssertEqual(viewModel.state.weeklyStats.durationLabel, "44m")
        XCTAssertEqual(viewModel.state.recentWorkouts.map(\.name), ["Upper Body", "Quick Strength"])
        XCTAssertEqual(viewModel.state.postureSummary, "3 assessments · latest Oct 10")
    }

    func testProgressActionsOpenHistoryAndSwitchToPostureTab() {
        let router = AppRouter()
        let viewModel = ProgressViewModel(
            workoutHistory: MemoryWorkoutHistoryRepository(records: []),
            assessments: MemoryAssessmentRepository(assessments: []),
            router: router,
            now: { FixedClock.date },
            calendar: FixedClock.calendar
        )

        viewModel.send(.openHistory)
        XCTAssertEqual(router.selectedTab, .progress)
        XCTAssertEqual(router.path(for: .progress), [.history])

        viewModel.send(.openPosture)
        XCTAssertEqual(router.selectedTab, .posture)
    }

    func testHistoryViewModelGroupsRecordsAndOpensSelectedRecord() throws {
        let latest = makeRecord(start: date(2026, 10, 14, hour: 10), duration: 26, name: "Upper Body", reps: [10, 9])
        let previous = makeRecord(start: date(2026, 10, 7, hour: 10), duration: 18, name: "Quick Strength", reps: [10])
        let repository = MemoryWorkoutHistoryRepository(records: [previous, latest])
        let viewModel = HistoryViewModel(repository: repository, exerciseCatalog: LiveExerciseCatalog(), now: { FixedClock.date }, calendar: FixedClock.calendar)

        XCTAssertEqual(viewModel.state.groups.map(\.title), ["This week", "Last week"])
        XCTAssertEqual(try XCTUnwrap(viewModel.openRecord(id: latest.id)), latest)
    }

    func testHistoryViewModelDeletesWorkout() {
        let record = makeRecord(start: date(2026, 10, 14, hour: 10), duration: 26, name: "Upper Body", reps: [10, 9])
        let repository = MemoryWorkoutHistoryRepository(records: [record])
        let viewModel = HistoryViewModel(repository: repository, exerciseCatalog: LiveExerciseCatalog(), now: { FixedClock.date }, calendar: FixedClock.calendar)

        viewModel.delete(recordID: record.id)

        XCTAssertTrue(repository.records.isEmpty)
        XCTAssertTrue(viewModel.state.groups.isEmpty)
    }

    func testHistoryViewModelPersistsWeightEditForCurrentAndLaterSets() throws {
        let record = makeRecord(start: date(2026, 10, 14, hour: 10), duration: 26, name: "Upper Body", reps: [10, 9, 8])
        let repository = MemoryWorkoutHistoryRepository(records: [record])
        let viewModel = HistoryViewModel(repository: repository, exerciseCatalog: LiveExerciseCatalog(), now: { FixedClock.date }, calendar: FixedClock.calendar)
        let entry = try XCTUnwrap(record.entries.first)

        viewModel.updateWeight(
            recordID: record.id,
            entryID: entry.id,
            setIndex: 0,
            weight: .mass(20, .pounds),
            applyToLater: true
        )

        XCTAssertEqual(repository.records.first?.entries.first?.sets.map(\.weight), [
            .mass(20, .pounds), .mass(20, .pounds), .mass(20, .pounds)
        ])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int) -> Date {
        FixedClock.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func makeRecord(start: Date, duration: Int, name: String, reps: [Int]) -> WorkoutRecord {
        WorkoutRecord(
            startedAt: start,
            endedAt: start.addingTimeInterval(Double(duration * 60)),
            planName: name,
            entries: [WorkoutRecordEntry(
                exerciseID: .shoulderPress,
                name: "Shoulder Press",
                outcome: .completed,
                sets: reps.map { RecordedSet(reps: $0, side: nil, weight: nil) }
            )]
        )
    }

    private func makeAssessment(date: Date) -> PostureAssessment {
        PostureAssessment(
            date: date,
            imageRelativePath: "assessment.jpg",
            view: .front,
            pose: BodyPose(landmarks: [:], imageWidth: 100, imageHeight: 200),
            measurements: []
        )
    }
}

@MainActor
private final class MemoryWorkoutHistoryRepository: WorkoutHistoryRepository {
    var records: [WorkoutRecord]

    init(records: [WorkoutRecord]) { self.records = records }

    func list() throws -> [WorkoutRecord] { records.sorted { $0.startedAt > $1.startedAt } }

    func save(_ record: WorkoutRecord) throws {
        records.removeAll { $0.id == record.id }
        records.append(record)
    }

    func updateWeights(for record: WorkoutRecord) throws {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index] = record
    }

    func delete(id: UUID) throws { records.removeAll { $0.id == id } }
}

@MainActor
private final class MemoryAssessmentRepository: AssessmentRepository {
    let assessments: [PostureAssessment]

    init(assessments: [PostureAssessment]) { self.assessments = assessments }

    func list() throws -> [PostureAssessment] { assessments }
    func save(_ assessment: PostureAssessment, imageRelativePath: String) throws {}
    func setBaseline(id: UUID, isBaseline: Bool) throws {}
    func delete(id: UUID) throws {}
}
