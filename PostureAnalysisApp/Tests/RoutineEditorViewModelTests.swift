import Foundation
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class RoutineEditorViewModelTests: XCTestCase {
    private let catalog: any ExerciseCatalogProviding = LiveExerciseCatalog()

    func testCreateModeStartsEmptyWithSaveDisabled() {
        let viewModel = makeViewModel()

        XCTAssertTrue(viewModel.state.isNew)
        XCTAssertEqual(viewModel.state.name, "")
        XCTAssertTrue(viewModel.state.items.isEmpty)
        XCTAssertFalse(viewModel.state.isSaveEnabled)
    }

    func testNameAloneDoesNotEnableSaveButNameAndOneExerciseDoes() {
        let viewModel = makeViewModel()

        viewModel.send(.nameChanged("Morning Strength"))
        XCTAssertFalse(viewModel.state.isSaveEnabled)

        viewModel.send(.addExercise(.shoulderPress))
        XCTAssertTrue(viewModel.state.isSaveEnabled)
    }

    func testSummaryUpdatesOnAddRemoveAndStepperChanges() throws {
        let viewModel = makeViewModel()
        viewModel.send(.addExercise(.shoulderPress))
        let rowID = try XCTUnwrap(viewModel.state.items.first?.id)

        XCTAssertEqual(viewModel.state.summary, "1 exercise · 2 sets")

        viewModel.send(.setCountChanged(itemID: rowID, value: 4))
        XCTAssertEqual(viewModel.state.summary, "1 exercise · 4 sets")
        XCTAssertEqual(viewModel.state.items[0].targetLabel, "4 × 8–10")

        viewModel.send(.addExercise(.airSquat))
        XCTAssertEqual(viewModel.state.summary, "2 exercises · 6 sets")

        let secondID = try XCTUnwrap(viewModel.state.items.last?.id)
        viewModel.send(.removeExercise(secondID))
        XCTAssertEqual(viewModel.state.summary, "1 exercise · 4 sets")
    }

    func testStepperBoundsAndRepRangeStayValid() throws {
        let viewModel = makeViewModel()
        viewModel.send(.addExercise(.shoulderPress))
        let id = try XCTUnwrap(viewModel.state.items.first?.id)

        viewModel.send(.setCountChanged(itemID: id, value: 99))
        XCTAssertEqual(viewModel.state.items[0].setCount, 10)
        viewModel.send(.setCountChanged(itemID: id, value: 0))
        XCTAssertEqual(viewModel.state.items[0].setCount, 1)

        viewModel.send(.minimumRepsChanged(itemID: id, value: 50))
        XCTAssertEqual(viewModel.state.items[0].minimumReps, 50)
        XCTAssertEqual(viewModel.state.items[0].maximumReps, 50)
        viewModel.send(.maximumRepsChanged(itemID: id, value: 1))
        XCTAssertEqual(viewModel.state.items[0].maximumReps, 1)
        XCTAssertEqual(viewModel.state.items[0].minimumReps, 1)
        viewModel.send(.minimumRepsChanged(itemID: id, value: 0))
        XCTAssertEqual(viewModel.state.items[0].minimumReps, 1)
    }

    func testMoveUpAndDownReordersWithBoundsAtEnds() throws {
        let viewModel = makeViewModel()
        viewModel.send(.addExercise(.shoulderPress))
        viewModel.send(.addExercise(.hammerCurl))
        viewModel.send(.addExercise(.airSquat))
        let ids = viewModel.state.items.map(\.id)

        viewModel.send(.moveUp(ids[0]))
        XCTAssertEqual(viewModel.state.items.map(\.id), ids)

        viewModel.send(.moveDown(ids[2]))
        XCTAssertEqual(viewModel.state.items.map(\.id), ids)

        viewModel.send(.moveDown(ids[0]))
        XCTAssertEqual(viewModel.state.items.map(\.id), [ids[1], ids[0], ids[2]])

        viewModel.send(.moveUp(ids[2]))
        XCTAssertEqual(viewModel.state.items.map(\.id), [ids[1], ids[2], ids[0]])
    }

    func testDragMoveIntentReordersToDropPosition() throws {
        let viewModel = makeViewModel()
        viewModel.send(.addExercise(.shoulderPress))
        viewModel.send(.addExercise(.hammerCurl))
        viewModel.send(.addExercise(.airSquat))
        let ids = viewModel.state.items.map(\.id)

        viewModel.send(.move(from: 0, to: 3))

        XCTAssertEqual(viewModel.state.items.map(\.id), [ids[1], ids[2], ids[0]])
    }

    func testEditingSavePreservesIdentityAndCreationDateAndUpdatesUpdateDate() throws {
        let original = routine(name: "Upper Body", ids: [.shoulderPress])
        let createdAt = Date(timeIntervalSince1970: 100)
        let updatedAt = Date(timeIntervalSince1970: 150)
        let now = Date(timeIntervalSince1970: 200)
        let repository = RoutineEditorTestRepository(records: [
            SavedExerciseSetRecord(set: original, createdAt: createdAt, updatedAt: updatedAt)
        ], now: { now })
        let viewModel = makeViewModel(id: original.id, repository: repository)

        viewModel.send(.nameChanged("  Upper Body Plus  "))
        viewModel.send(.save)

        let record = try XCTUnwrap(repository.records.first)
        XCTAssertEqual(record.set.id, original.id)
        XCTAssertEqual(record.set.name, "Upper Body Plus")
        XCTAssertEqual(record.createdAt, createdAt)
        XCTAssertGreaterThan(record.updatedAt, updatedAt)
    }

    func testDeleteRequiresConfirmationThenDeletesAndPopsToRoutinesRoot() throws {
        let original = routine(name: "Upper Body", ids: [.shoulderPress])
        let repository = RoutineEditorTestRepository(records: [
            SavedExerciseSetRecord(set: original, createdAt: .distantPast, updatedAt: .distantPast)
        ])
        let router = AppRouter(selectedTab: .routines)
        router.setPath([.routine(id: original.id), .routineEditor(id: original.id)], for: .routines)
        let viewModel = makeViewModel(id: original.id, repository: repository, router: router)

        viewModel.send(.requestDelete)
        XCTAssertTrue(viewModel.state.showsDeleteConfirmation)
        XCTAssertEqual(repository.records.count, 1)

        viewModel.send(.confirmDelete)
        XCTAssertTrue(repository.records.isEmpty)
        XCTAssertEqual(router.path(for: .routines), [])
    }

    func testCancelDiscardsEditsAndReturnsToPreviousRoute() throws {
        let original = routine(name: "Upper Body", ids: [.shoulderPress])
        let repository = RoutineEditorTestRepository(records: [
            SavedExerciseSetRecord(set: original, createdAt: .distantPast, updatedAt: .distantPast)
        ])
        let router = AppRouter(selectedTab: .routines)
        router.setPath([.routine(id: original.id), .routineEditor(id: original.id)], for: .routines)
        let viewModel = makeViewModel(id: original.id, repository: repository, router: router)

        viewModel.send(.nameChanged("Discard this"))
        viewModel.send(.addExercise(.airSquat))
        viewModel.send(.cancel)

        XCTAssertEqual(repository.records.first?.set, original)
        XCTAssertEqual(router.path(for: .routines), [.routine(id: original.id)])
    }

    func testPickerSortOptionsOrderExercisesByTargetAndRoutineOccurrences() {
        let viewModel = makeViewModel()
        viewModel.send(.addExercise(.shoulderPress))
        viewModel.send(.addExercise(.shoulderPress))
        viewModel.send(.presentPicker)

        XCTAssertEqual(viewModel.state.pickerExercises.first?.exerciseID, .shoulderPress)
        viewModel.send(.sortPicker(.mostReps))
        let maximums = viewModel.state.pickerExercises.map { catalog.exercise($0.exerciseID)!.targetReps.upperBound }
        XCTAssertEqual(maximums, maximums.sorted(by: >))

        viewModel.send(.sortPicker(.fewestReps))
        let minimums = viewModel.state.pickerExercises.map { catalog.exercise($0.exerciseID)!.targetReps.lowerBound }
        XCTAssertEqual(minimums, minimums.sorted())
        XCTAssertEqual(viewModel.state.pickerExercises.first?.inRoutineCount, 2)
        XCTAssertEqual(viewModel.state.pickerSort, .fewestReps)
    }

    func testPickerSearchUsesExerciseFilterForEquipmentAndMultipleTokens() {
        let viewModel = makeViewModel()
        viewModel.send(.presentPicker)

        viewModel.send(.pickerSearchChanged("  triceps band  "))

        XCTAssertEqual(viewModel.state.pickerSearchText, "  triceps band  ")
        XCTAssertEqual(viewModel.state.pickerExercises.map(\.exerciseID), [.tricepsExtension])
        XCTAssertEqual(viewModel.state.pickerSort, .inRoutine)

        viewModel.send(.pickerSearchChanged("unlisted movement"))
        XCTAssertTrue(viewModel.state.pickerExercises.isEmpty)
    }

    private func makeViewModel(
        id: UUID? = nil,
        repository: RoutineEditorTestRepository? = nil,
        router: AppRouter? = nil
    ) -> RoutineEditorViewModel {
        RoutineEditorViewModel(
            id: id,
            routines: repository ?? RoutineEditorTestRepository(),
            exerciseCatalog: catalog,
            router: router ?? AppRouter(selectedTab: .routines)
        )
    }

    private func routine(name: String, ids: [ExerciseID]) -> SavedExerciseSet {
        SavedExerciseSet(name: name, items: ids.map { id in
            SavedExerciseSetItem(exerciseID: id, setCount: 2, targetRepMinimum: 8, targetRepMaximum: 10)
        })
    }
}

@MainActor
private final class RoutineEditorTestRepository: RoutineRepository {
    private(set) var records: [SavedExerciseSetRecord]
    private let now: () -> Date

    init(records: [SavedExerciseSetRecord] = [], now: @escaping () -> Date = Date.init) {
        self.records = records
        self.now = now
    }

    func list() throws -> [SavedExerciseSet] { records.map(\.set) }
    func listWithUpdateDates() throws -> [SavedExerciseSetRecord] { records }

    func save(_ set: SavedExerciseSet) throws {
        if let index = records.firstIndex(where: { $0.set.id == set.id }) {
            records[index] = SavedExerciseSetRecord(
                set: set,
                createdAt: records[index].createdAt,
                updatedAt: now()
            )
        } else {
            records.append(SavedExerciseSetRecord(set: set, createdAt: now(), updatedAt: now()))
        }
    }

    func duplicate(_ set: SavedExerciseSet) throws -> SavedExerciseSet {
        let copy = set.duplicated()
        try save(copy)
        return copy
    }

    func delete(id: UUID) throws { records.removeAll { $0.set.id == id } }
}
