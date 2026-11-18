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

    func testViewChoiceReadsAndWritesTheRememberedCameraPreference() throws {
        let preferences = InMemoryPreferences()
        preferences.setViewPreference(.locked(.sideOn), for: .hammerCurl)
        let viewModel = makeViewModel(id: .hammerCurl, preferences: preferences)

        XCTAssertTrue(viewModel.state.hasViewChoice)
        XCTAssertEqual(viewModel.state.viewPreference, .locked(.sideOn))
        XCTAssertEqual(viewModel.state.cameraSetupText, "Side-on")

        viewModel.send(.cameraViewSelected(.locked(.facing)))

        XCTAssertEqual(preferences.viewPreference(for: .hammerCurl), .locked(.facing))
        XCTAssertEqual(viewModel.state.viewPreference, .locked(.facing))
        XCTAssertEqual(viewModel.state.cameraSetupText, "Front")

        viewModel.send(.cameraViewSelected(.auto))

        XCTAssertEqual(preferences.viewPreference(for: .hammerCurl), .auto)
        XCTAssertEqual(viewModel.state.viewPreference, .auto)
        XCTAssertEqual(viewModel.state.cameraSetupText, "Auto")
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

    func testSideOnStepsFollowSavedSelectedAndRefreshedCameraView() throws {
        let preferences = InMemoryPreferences()
        preferences.setViewPreference(.locked(.sideOn), for: .hammerCurl)
        let viewModel = makeViewModel(id: .hammerCurl, preferences: preferences)
        let exercise = try XCTUnwrap(catalog.exercise(.hammerCurl))
        let facingView = try XCTUnwrap(exercise.view(for: .facing))
        let sideOnView = try XCTUnwrap(exercise.view(for: .sideOn))
        let facingSteps = exercise.inView(facingView).guide.steps
        let sideOnSteps = exercise.inView(sideOnView).guide.steps

        XCTAssertNotEqual(sideOnSteps, facingSteps)
        XCTAssertEqual(viewModel.state.steps, sideOnSteps)
        XCTAssertEqual(viewModel.state.steps.first?.detail,
                       "Stand tall, side-on to the phone. Let the dumbbells hang at your sides with straight arms, palms facing in.")
        XCTAssertEqual(viewModel.state.steps.last?.detail,
                       "Lower them slowly until your arms are straight again. That's one rep.")

        viewModel.send(.cameraViewSelected(.locked(.facing)))
        XCTAssertEqual(viewModel.state.steps, facingSteps)

        viewModel.send(.cameraViewSelected(.locked(.sideOn)))
        XCTAssertEqual(viewModel.state.steps, sideOnSteps)

        preferences.setViewPreference(.locked(.facing), for: .hammerCurl)
        viewModel.send(.appeared)
        XCTAssertEqual(viewModel.state.steps, facingSteps)

        preferences.setViewPreference(.locked(.sideOn), for: .hammerCurl)
        viewModel.send(.appeared)
        XCTAssertEqual(viewModel.state.steps, sideOnSteps)
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
        id: ExerciseID = .shoulderPress,
        preferences: any AppPreferencesStoring = InMemoryPreferences(),
        router: AppRouter? = nil
    ) -> ExerciseDetailViewModel {
        ExerciseDetailViewModel(
            id: id,
            exerciseCatalog: catalog,
            preferences: preferences,
            router: router ?? AppRouter(selectedTab: .train)
        )
    }
}
