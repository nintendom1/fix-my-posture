import Foundation
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class TrainHomeViewModelTests: XCTestCase {
    private let catalog = MemoryExerciseCatalog(exercises: [
        ShoulderPressExercise.definition(),
        HammerCurlExercise.definition(),
        TricepsExtensionExercise.definition(),
        AirSquatExercise.definition(),
        DumbbellRowExercise.definition(),
        PushUpExercise.definition()
    ])

    func testHeroUsesUpNextRoutineRatherThanMostRecentlyUpdatedRoutine() throws {
        let older = routine(name: "Older", ids: [.shoulderPress])
        let newest = routine(name: "Upper Body", ids: [.shoulderPress, .dumbbellRow, .hammerCurl, .tricepsExtension])
        let repository = MemoryRoutineRepository(entries: [
            SavedExerciseSetRecord(set: newest, createdAt: Date(timeIntervalSince1970: 20), updatedAt: Date(timeIntervalSince1970: 200)),
            SavedExerciseSetRecord(set: older, createdAt: Date(timeIntervalSince1970: 10), updatedAt: Date(timeIntervalSince1970: 100))
        ])
        let viewModel = makeViewModel(routines: repository)

        XCTAssertEqual(viewModel.state.heroRoutine?.id, older.id)
        XCTAssertEqual(viewModel.state.heroRoutine?.name, "Older")
    }

    func testPickAnotherOpensChoicesAndSelectionPersistsOverrideAndUpdatesHero() {
        let first = routine(name: "First", ids: [.shoulderPress])
        let second = routine(name: "Second", ids: [.airSquat])
        let repository = MemoryRoutineRepository(entries: [
            SavedExerciseSetRecord(set: first, createdAt: Date(timeIntervalSince1970: 10), updatedAt: Date(timeIntervalSince1970: 20)),
            SavedExerciseSetRecord(set: second, createdAt: Date(timeIntervalSince1970: 20), updatedAt: Date(timeIntervalSince1970: 10))
        ])
        let preferences = InMemoryPreferences()
        let viewModel = makeViewModel(routines: repository, preferences: preferences)

        XCTAssertEqual(viewModel.state.heroRoutine?.id, first.id)
        viewModel.send(.pickAnother)
        XCTAssertTrue(viewModel.state.isRoutinePickerPresented)
        XCTAssertEqual(Set(viewModel.state.routineChoices.map(\.id)), Set([first.id, second.id]))

        viewModel.send(.selectRoutine(second.id))

        XCTAssertEqual(preferences.upNextOverride, second.id)
        XCTAssertEqual(viewModel.state.heroRoutine?.id, second.id)
        XCTAssertFalse(viewModel.state.isRoutinePickerPresented)
    }

    func testHeroChipsTruncateToThreeAndThenShowRemainingCount() {
        let savedSet = routine(name: "Upper Body", ids: [.shoulderPress, .dumbbellRow, .hammerCurl, .tricepsExtension])
        let viewModel = makeViewModel(routines: MemoryRoutineRepository(entries: [
            SavedExerciseSetRecord(set: savedSet, updatedAt: FixedClock.date)
        ]))

        XCTAssertEqual(viewModel.state.heroRoutine?.chips, ["Shoulder Press", "Row", "Hammer Curl", "+1"])
    }

    func testRoutineSummaryIncludesTheDurationEstimate() {
        let savedSet = routine(name: "Upper Body", ids: [.shoulderPress, .dumbbellRow, .hammerCurl, .tricepsExtension])
        let viewModel = makeViewModel(routines: MemoryRoutineRepository(entries: [
            SavedExerciseSetRecord(set: savedSet, updatedAt: FixedClock.date)
        ]))
        let hero = viewModel.state.heroRoutine

        XCTAssertEqual(hero?.summaryWithEstimate, "4 exercises · 8 sets · about 25 min")
        XCTAssertNotNil(hero?.estimatedMinutes)
    }

    func testNoRoutinesShowsTheCreateRoutineEmptyState() {
        let viewModel = makeViewModel(routines: MemoryRoutineRepository(entries: []))

        XCTAssertNil(viewModel.state.heroRoutine)
        XCTAssertTrue(viewModel.state.showsCreateRoutineEmptyState)
    }

    func testStartRoutineOpensWorkoutRouteForHeroRoutine() throws {
        let savedSet = routine(name: "Upper Body", ids: [.shoulderPress, .dumbbellRow])
        let router = AppRouter()
        let viewModel = makeViewModel(routines: MemoryRoutineRepository(entries: [
            SavedExerciseSetRecord(set: savedSet, updatedAt: FixedClock.date)
        ]), router: router)

        viewModel.send(.startRoutine)

        XCTAssertEqual(router.presentedFullScreenRoute, .workout(exerciseID: nil, routineID: savedSet.id))
    }

    func testExerciseTileTapOpensWorkoutRouteForThatExercise() {
        let router = AppRouter()
        let viewModel = makeViewModel(routines: MemoryRoutineRepository(entries: []), router: router)

        viewModel.send(.startExercise(.airSquat))

        XCTAssertEqual(router.presentedFullScreenRoute, .workout(exerciseID: .airSquat, routineID: nil))
    }

    func testGearOpensSettings() {
        let router = AppRouter()
        let viewModel = makeViewModel(routines: MemoryRoutineRepository(entries: []), router: router)

        viewModel.send(.openSettings)

        XCTAssertEqual(router.presentedFullScreenRoute, .settings)
    }

    func testPersonaIntroAppearsWhenEnabledAndDismissalPersists() {
        let preferences = InMemoryPreferences()
        preferences.workoutReminderSettings = WorkoutReminderSettings(enabled: true, style: .character)
        let viewModel = makeViewModel(routines: MemoryRoutineRepository(entries: []), preferences: preferences)

        XCTAssertTrue(viewModel.state.showsPersonaIntro)

        viewModel.send(.dismissPersonaIntro)

        XCTAssertFalse(viewModel.state.showsPersonaIntro)
        XCTAssertTrue(preferences.personaIntroCardDismissed)
    }

    func testAllExercisesOpensLibrary() {
        let router = AppRouter()
        let viewModel = makeViewModel(routines: MemoryRoutineRepository(entries: []), router: router)

        viewModel.send(.openLibrary)

        XCTAssertEqual(router.selectedTab, .train)
        XCTAssertEqual(router.path(for: .train), [.library])
    }

    private func makeViewModel(
        routines: MemoryRoutineRepository,
        router: AppRouter? = nil,
        preferences: InMemoryPreferences = InMemoryPreferences()
    ) -> TrainHomeViewModel {
        TrainHomeViewModel(
            routines: routines,
            workoutHistory: MemoryWorkoutHistoryRepository(),
            exerciseCatalog: catalog,
            preferences: preferences,
            router: router ?? AppRouter(),
            now: { FixedClock.date }
        )
    }

    private func routine(name: String, ids: [ExerciseID]) -> SavedExerciseSet {
        SavedExerciseSet(name: name, items: ids.map { id in
            let exercise = catalog.exercise(id)!
            return SavedExerciseSetItem(
                exerciseID: id,
                setCount: 2,
                targetRepMinimum: exercise.targetReps.lowerBound,
                targetRepMaximum: exercise.targetReps.upperBound
            )
        })
    }
}

private struct MemoryExerciseCatalog: ExerciseCatalogProviding {
    let exercises: [ExerciseDefinition]

    var all: [ExerciseDefinition] { exercises }

    func exercise(_ id: ExerciseID) -> ExerciseDefinition? {
        exercises.first { $0.id == id }
    }
}

@MainActor
private final class MemoryRoutineRepository: RoutineRepository {
    var entries: [SavedExerciseSetRecord]

    init(entries: [SavedExerciseSetRecord]) {
        self.entries = entries
    }

    func list() throws -> [SavedExerciseSet] {
        entries.map(\.set)
    }

    func listWithUpdateDates() throws -> [SavedExerciseSetRecord] {
        entries
    }

    func save(_ set: SavedExerciseSet) throws {
        entries.removeAll { $0.set.id == set.id }
        entries.append(SavedExerciseSetRecord(set: set, updatedAt: FixedClock.date))
    }

    func duplicate(_ set: SavedExerciseSet) throws -> SavedExerciseSet {
        let copy = set.duplicated()
        try save(copy)
        return copy
    }

    func delete(id: UUID) throws {
        entries.removeAll { $0.set.id == id }
    }
}

@MainActor
private final class MemoryWorkoutHistoryRepository: WorkoutHistoryRepository {
    func list() throws -> [WorkoutRecord] { [] }
    func save(_ record: WorkoutRecord) throws {}
    func updateWeights(for record: WorkoutRecord) throws {}
    func delete(id: UUID) throws {}
}
