import Foundation
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class LibraryViewModelTests: XCTestCase {
    private let catalog: any ExerciseCatalogProviding = LiveExerciseCatalog()

    func testGroupsFollowCatalogOrderAndExerciseFilterGroups() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.state.selectedFilter, .all)
        XCTAssertEqual(viewModel.state.query, "")
        XCTAssertEqual(viewModel.state.groups.map(\.title), ["Upper body", "Lower body"])
        XCTAssertEqual(viewModel.state.groups[0].exercises.map(\.id), [
            .shoulderPress, .lateralRaise, .hammerCurl, .tricepsExtension, .dumbbellRow, .dumbbellShrug, .pushUp, .wallPushUp,
            .inclinePushUp
        ])
        XCTAssertEqual(viewModel.state.groups[1].exercises.map(\.id), [.airSquat, .stiffLegDeadlift, .rearLunge, .gluteBridge])
    }

    func testFilterChipAndQueryUpdateStateAndResults() {
        let viewModel = makeViewModel()

        viewModel.send(.filterSelected(.dumbbells))
        XCTAssertEqual(viewModel.state.selectedFilter, .dumbbells)
        XCTAssertEqual(viewModel.state.groups.map(\.title), ["Upper body", "Lower body"])
        XCTAssertEqual(viewModel.state.groups.flatMap(\.exercises).map(\.id), [
            .shoulderPress, .lateralRaise, .hammerCurl, .dumbbellRow, .dumbbellShrug, .stiffLegDeadlift, .rearLunge
        ])

        viewModel.send(.queryChanged("  press  "))
        XCTAssertEqual(viewModel.state.query, "  press  ")
        XCTAssertEqual(viewModel.state.groups.flatMap(\.exercises).map(\.id), [.shoulderPress])
    }

    func testEmptyGroupsAreHiddenAndNoMatchesOffersClearFilters() {
        let viewModel = makeViewModel()

        viewModel.send(.filterSelected(.lower))
        XCTAssertEqual(viewModel.state.groups.map(\.title), ["Lower body"])

        viewModel.send(.queryChanged("nothing matches"))
        XCTAssertTrue(viewModel.state.groups.isEmpty)
        XCTAssertEqual(viewModel.state.emptyState, .noMatches)

        viewModel.send(.clearFilters)
        XCTAssertEqual(viewModel.state.selectedFilter, .all)
        XCTAssertEqual(viewModel.state.query, "")
        XCTAssertNil(viewModel.state.emptyState)
        XCTAssertEqual(viewModel.state.groups.map(\.title), ["Upper body", "Lower body"])
    }

    func testRowsShowSavedSetsAndRepsTargetAndMostRecentWeight() throws {
        let preferences = InMemoryPreferences()
        ExerciseTargetStore.setTarget(
            ExerciseTarget(sets: 3, repMinimum: 6, repMaximum: 8),
            for: .shoulderPress,
            preferences: preferences
        )
        let history = LibraryTestWorkoutHistoryRepository(records: [
            workoutRecord(endedAt: 200, exerciseID: .shoulderPress, weight: .mass(20, .pounds))
        ])
        let viewModel = makeViewModel(preferences: preferences, history: history)
        let row = try XCTUnwrap(viewModel.state.groups.flatMap(\.exercises).first { $0.id == .shoulderPress })

        XCTAssertEqual(row.target, "3 × 6–8")
        XCTAssertEqual(row.weight, "20 lb")
    }

    func testRearLungeTargetNamesEachLeg() throws {
        let viewModel = makeViewModel()
        let row = try XCTUnwrap(viewModel.state.groups.flatMap(\.exercises).first { $0.id == .rearLunge })

        XCTAssertEqual(row.target, "2 × 8 each leg")
    }

    func testTappingAnExerciseRoutesToItsDetail() {
        let router = AppRouter(selectedTab: .train)
        router.setPath([.library], for: .train)
        let viewModel = makeViewModel(router: router)

        viewModel.send(.exerciseSelected(.shoulderPress))

        XCTAssertEqual(router.path(for: .train), [.library, .exercise(id: .shoulderPress)])
    }

    private func makeViewModel(
        preferences: any AppPreferencesStoring = InMemoryPreferences(),
        history: (any WorkoutHistoryRepository)? = nil,
        router: AppRouter? = nil
    ) -> LibraryViewModel {
        LibraryViewModel(
            workoutHistory: history,
            exerciseCatalog: catalog,
            preferences: preferences,
            router: router ?? AppRouter(selectedTab: .train)
        )
    }

    private func workoutRecord(endedAt: TimeInterval, exerciseID: ExerciseID, weight: WorkoutWeight) -> WorkoutRecord {
        WorkoutRecord(
            startedAt: Date(timeIntervalSince1970: endedAt - 60),
            endedAt: Date(timeIntervalSince1970: endedAt),
            planName: nil,
            entries: [WorkoutRecordEntry(
                exerciseID: exerciseID,
                name: catalog.exercise(exerciseID)!.displayName,
                sets: [RecordedSet(reps: 8, weight: weight)]
            )]
        )
    }
}

@MainActor
private final class LibraryTestWorkoutHistoryRepository: WorkoutHistoryRepository {
    private let records: [WorkoutRecord]

    init(records: [WorkoutRecord]) {
        self.records = records
    }

    func list() throws -> [WorkoutRecord] { records }
    func save(_ record: WorkoutRecord) throws {}
    func updateWeights(for record: WorkoutRecord) throws {}
    func delete(id: UUID) throws {}
}
