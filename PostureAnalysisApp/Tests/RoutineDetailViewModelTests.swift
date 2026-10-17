import Foundation
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class RoutineDetailViewModelTests: XCTestCase {
    private let catalog: any ExerciseCatalogProviding = LiveExerciseCatalog()

    func testSummaryIncludesDurationAndLastDoneDate() {
        let savedSet = routine(name: "Upper Body", ids: [.shoulderPress, .dumbbellRow, .hammerCurl, .tricepsExtension])
        let endedAt = FixedClock.calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))!
        let history = RoutinesTestWorkoutHistoryRepository(records: [WorkoutRecord(
            startedAt: endedAt.addingTimeInterval(-60),
            endedAt: endedAt,
            planID: savedSet.id,
            planName: savedSet.name,
            entries: []
        )])
        let viewModel = makeViewModel(for: savedSet, repository: RoutinesTestRepository(sets: [savedSet]),
                                      history: history, now: { FixedClock.date })

        XCTAssertEqual(viewModel.state.routine?.summary, "4 exercises · 8 sets · about 25 min")
        XCTAssertEqual(viewModel.state.routine?.lastDoneLabel, "Last done Wed, Oct 14")
    }

    func testSequenceShowsMostRecentKnownWeightForTheRoutine() {
        let savedSet = routine(name: "Upper Body", ids: [.shoulderPress])
        let record = WorkoutRecord(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 10),
            endedAt: Date(timeIntervalSince1970: 20),
            planID: savedSet.id,
            planName: savedSet.name,
            entries: [WorkoutRecordEntry(
                exerciseID: .shoulderPress,
                name: "Shoulder Press",
                outcome: .completed,
                sets: [RecordedSet(reps: 10, weight: .mass(20, .pounds))]
            )]
        )
        let history = RoutinesTestWorkoutHistoryRepository(records: [record])
        let viewModel = makeViewModel(
            for: savedSet,
            repository: RoutinesTestRepository(sets: [savedSet]),
            history: history
        )

        XCTAssertEqual(viewModel.state.routine?.steps.first?.targetLine, "2 × 8–10 · 20 lb")
    }

    func testDuplicateUsesRoutineRepositoryAndTodayCopyName() {
        let savedSet = routine(name: "Upper Body", ids: [.shoulderPress])
        let repository = RoutinesTestRepository(sets: [savedSet])
        let viewModel = makeViewModel(for: savedSet, repository: repository)

        viewModel.send(.duplicate)

        XCTAssertEqual(repository.duplicateInputs, [savedSet.id])
        XCTAssertEqual(repository.sets.map(\.name), ["Upper Body", "Upper Body Copy"])
    }

    func testDeleteAsksForConfirmationBeforeRemovingRoutine() {
        let savedSet = routine(name: "Upper Body", ids: [.shoulderPress])
        let repository = RoutinesTestRepository(sets: [savedSet])
        let viewModel = makeViewModel(for: savedSet, repository: repository)

        viewModel.send(.requestDelete)

        XCTAssertTrue(viewModel.state.showsDeleteConfirmation)
        XCTAssertEqual(repository.sets.map(\.id), [savedSet.id])
    }

    func testConfirmDeleteRemovesRoutineAndPopsBackToRoutines() {
        let savedSet = routine(name: "Upper Body", ids: [.shoulderPress])
        let repository = RoutinesTestRepository(sets: [savedSet])
        let router = AppRouter(selectedTab: .routines)
        router.setPath([.routine(id: savedSet.id)], for: .routines)
        let viewModel = makeViewModel(for: savedSet, repository: repository, router: router)

        viewModel.send(.requestDelete)
        viewModel.send(.confirmDelete)

        XCTAssertEqual(repository.sets, [])
        XCTAssertNil(viewModel.state.routine)
        XCTAssertEqual(router.path(for: .routines), [])
    }

    func testStartSendsTheRoutineWorkoutRoute() {
        let savedSet = routine(name: "Upper Body", ids: [.shoulderPress])
        let router = AppRouter(selectedTab: .routines)
        let viewModel = makeViewModel(
            for: savedSet,
            repository: RoutinesTestRepository(sets: [savedSet]),
            router: router
        )

        viewModel.send(.start)

        XCTAssertEqual(router.presentedFullScreenRoute, .workout(exerciseID: nil, routineID: savedSet.id))
    }

    func testEditPushesTheLegacySavedSetEditorRoute() {
        let savedSet = routine(name: "Upper Body", ids: [.shoulderPress])
        let router = AppRouter(selectedTab: .routines)
        router.setPath([.routine(id: savedSet.id)], for: .routines)
        let viewModel = makeViewModel(
            for: savedSet,
            repository: RoutinesTestRepository(sets: [savedSet]),
            router: router
        )

        viewModel.send(.edit)

        XCTAssertEqual(router.path(for: .routines), [
            .routine(id: savedSet.id),
            .routineEditor(id: savedSet.id)
        ])
    }

    private func makeViewModel(
        for savedSet: SavedExerciseSet,
        repository: RoutinesTestRepository,
        router: AppRouter? = nil,
        history: RoutinesTestWorkoutHistoryRepository? = nil,
        now: @escaping () -> Date = Date.init
    ) -> RoutineDetailViewModel {
        RoutineDetailViewModel(
            id: savedSet.id,
            routines: repository,
            workoutHistory: history ?? RoutinesTestWorkoutHistoryRepository(),
            exerciseCatalog: catalog,
            preferences: InMemoryPreferences(),
            router: router ?? AppRouter(selectedTab: .routines),
            now: now,
            calendar: FixedClock.calendar
        )
    }

    private func routine(name: String, ids: [ExerciseID]) -> SavedExerciseSet {
        SavedExerciseSet(name: name, items: ids.map { id in
            let exercise = catalog.exercise(id)!
            return SavedExerciseSetItem(exerciseID: id, setCount: 2,
                                        targetRepMinimum: exercise.targetReps.lowerBound,
                                        targetRepMaximum: exercise.targetReps.upperBound)
        })
    }
}
