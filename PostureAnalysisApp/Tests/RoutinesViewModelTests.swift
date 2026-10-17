import Foundation
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class RoutinesViewModelTests: XCTestCase {
    private let catalog: any ExerciseCatalogProviding = LiveExerciseCatalog()

    func testListUsesCreatedAtOrderLikeTheLegacySavedSetList() {
        let early = routine(name: "Early", ids: [.shoulderPress])
        let late = routine(name: "Late", ids: [.airSquat])
        let repository = RoutinesTestRepository(sets: [late, early], createdAt: [
            early.id: Date(timeIntervalSince1970: 10),
            late.id: Date(timeIntervalSince1970: 20)
        ])
        let viewModel = makeViewModel(repository: repository)

        XCTAssertEqual(viewModel.state.routines.map(\.name), ["Early", "Late"])
    }

    func testThemeComesFromTheFirstExercisePresentation() {
        let first = routine(name: "Upper Body", ids: [.shoulderPress, .airSquat])
        let viewModel = makeViewModel(repository: RoutinesTestRepository(sets: [first]))

        XCTAssertEqual(viewModel.state.routines.first?.theme, .exercise(catalog.exercise(.shoulderPress)!.presentation.gradient))
    }

    func testEmptyRoutineUsesBrandTheme() {
        let empty = SavedExerciseSet(name: "Empty", items: [])
        let viewModel = makeViewModel(repository: RoutinesTestRepository(sets: [empty]))

        XCTAssertEqual(viewModel.state.routines.first?.theme, .brand)
    }

    func testSummaryUsesExerciseAndSetCountsWithoutAnEstimate() {
        let upperBody = routine(name: "Upper Body", ids: [.shoulderPress, .dumbbellRow, .hammerCurl, .tricepsExtension])
        let viewModel = makeViewModel(repository: RoutinesTestRepository(sets: [upperBody]))

        XCTAssertEqual(viewModel.state.routines.first?.summary, "4 exercises · 8 sets")
    }

    func testCardStartOpensWorkoutRouteForItsRoutine() {
        let savedSet = routine(name: "Upper Body", ids: [.shoulderPress])
        let router = AppRouter()
        let viewModel = makeViewModel(repository: RoutinesTestRepository(sets: [savedSet]), router: router)

        viewModel.send(.start(savedSet.id))

        XCTAssertEqual(router.presentedFullScreenRoute, .workout(exerciseID: nil, routineID: savedSet.id))
    }

    func testCreateRoutineOpensTheLegacyEditorForANewRoutine() {
        let router = AppRouter()
        let viewModel = makeViewModel(repository: RoutinesTestRepository(sets: []), router: router)

        viewModel.send(.createRoutine)

        XCTAssertEqual(router.path(for: .routines), [.routineEditor(id: nil)])
    }

    func testDuplicateUsesRepositoryNaming() {
        let savedSet = routine(name: "Upper Body", ids: [.shoulderPress])
        let repository = RoutinesTestRepository(sets: [savedSet])
        let viewModel = makeViewModel(repository: repository)

        viewModel.send(.duplicate(savedSet.id))

        XCTAssertEqual(repository.sets.map(\.name), ["Upper Body", "Upper Body Copy"])
    }

    func testDeleteRequiresConfirmationAndRemovesTheSelectedRoutine() {
        let savedSet = routine(name: "Upper Body", ids: [.shoulderPress])
        let repository = RoutinesTestRepository(sets: [savedSet])
        let viewModel = makeViewModel(repository: repository)

        viewModel.send(.requestDelete(savedSet.id))

        XCTAssertTrue(viewModel.state.showsDeleteConfirmation)
        XCTAssertEqual(repository.sets.map(\.id), [savedSet.id])

        viewModel.send(.confirmDelete)

        XCTAssertEqual(repository.sets, [])
        XCTAssertEqual(viewModel.state.routines, [])
    }

    private func makeViewModel(
        repository: RoutinesTestRepository,
        router: AppRouter? = nil
    ) -> RoutinesViewModel {
        RoutinesViewModel(routines: repository, exerciseCatalog: catalog, router: router ?? AppRouter())
    }

    private func routine(name: String, ids: [ExerciseID]) -> SavedExerciseSet {
        SavedExerciseSet(name: name, items: ids.map { id in
            SavedExerciseSetItem(exerciseID: id, setCount: 2, targetRepMinimum: 8, targetRepMaximum: 10)
        })
    }
}
