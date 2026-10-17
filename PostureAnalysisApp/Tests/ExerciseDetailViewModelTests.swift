import Foundation
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class ExerciseDetailViewModelTests: XCTestCase {
    private let catalog: any ExerciseCatalogProviding = LiveExerciseCatalog()

    func testTilesUseExercisePresentationCopy() throws {
        let viewModel = makeViewModel()
        let exercise = try XCTUnwrap(catalog.exercise(.shoulderPress))

        XCTAssertEqual(viewModel.state.equipmentText, exercise.presentation.equipmentLine)
        XCTAssertEqual(viewModel.state.cameraSetupText, exercise.presentation.cameraSetupLine)
    }

    func testSetsStepperClampsAndPersistsTarget() throws {
        let preferences = InMemoryPreferences()
        let viewModel = makeViewModel(preferences: preferences)

        for _ in 0..<10 { viewModel.send(.decrementSets) }
        XCTAssertEqual(viewModel.state.sets, 1)
        for _ in 0..<20 { viewModel.send(.incrementSets) }
        XCTAssertEqual(viewModel.state.sets, 10)

        let stored = try XCTUnwrap(preferences.exerciseTarget(for: ExerciseID.shoulderPress.rawValue))
        XCTAssertEqual(stored, ExerciseTarget(sets: 10, repMinimum: 8, repMaximum: 10))
    }

    func testWatchItemsComeFromExercisePresentation() throws {
        let viewModel = makeViewModel()
        let exercise = try XCTUnwrap(catalog.exercise(.shoulderPress))

        XCTAssertEqual(viewModel.state.watchesFor, exercise.presentation.watchesFor.map(\.text))
    }

    func testStepsComeFromExerciseGuide() throws {
        let viewModel = makeViewModel()
        let exercise = try XCTUnwrap(catalog.exercise(.shoulderPress))

        XCTAssertEqual(viewModel.state.steps, exercise.guide.steps)
    }

    func testStartRoutesToTheSingleExerciseWorkout() {
        let router = AppRouter(selectedTab: .train)
        let viewModel = makeViewModel(router: router)

        viewModel.send(.startExercise)

        XCTAssertEqual(router.presentedFullScreenRoute, .workout(exerciseID: .shoulderPress, routineID: nil))
    }

    func testWatchGuidePresentsTheGuide() {
        let viewModel = makeViewModel()

        viewModel.send(.watchGuide)

        XCTAssertTrue(viewModel.state.isGuidePresented)
    }

    private func makeViewModel(
        preferences: any AppPreferencesStoring = InMemoryPreferences(),
        router: AppRouter? = nil
    ) -> ExerciseDetailViewModel {
        ExerciseDetailViewModel(
            id: .shoulderPress,
            exerciseCatalog: catalog,
            preferences: preferences,
            router: router ?? AppRouter(selectedTab: .train)
        )
    }
}
