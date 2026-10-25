import Foundation
import SwiftData
import XCTest
@testable import PostureAnalysisApp

@MainActor
final class BuiltInRoutineRepositoryTests: XCTestCase {
    func testListMergesUserRoutinesBeforeStarterRoutinesInCatalogOrder() throws {
        let (container, base, repository) = try makeRepository()
        let first = routine("First")
        let second = routine("Second")
        try base.save(first)
        try base.save(second)

        let listed = try repository.list()
        let userOrder = try base.list().map(\.id)
        XCTAssertEqual(Array(listed.prefix(userOrder.count)).map(\.id), userOrder)
        XCTAssertEqual(Array(listed.suffix(BuiltInRoutines.all.count)), BuiltInRoutines.all)

        let records = try repository.listWithUpdateDates()
        XCTAssertEqual(Array(records.suffix(BuiltInRoutines.all.count)).map(\.set), BuiltInRoutines.all)
        XCTAssertEqual(Array(records.suffix(BuiltInRoutines.all.count)).map(\.createdAt),
                       BuiltInRoutines.all.indices.map { Date.distantPast.addingTimeInterval(TimeInterval($0)) })
        _ = container
    }

    func testBuiltInSaveAndDeleteThrowWithoutChangingTheBaseStore() throws {
        let (container, base, repository) = try makeRepository()
        let user = routine("User routine")
        try base.save(user)
        let before = try base.list()
        let builtIn = try XCTUnwrap(BuiltInRoutines.all.first)

        XCTAssertThrowsError(try repository.save(builtIn)) {
            XCTAssertEqual($0 as? RoutineRepositoryError, .builtInRoutineIsReadOnly)
        }
        XCTAssertThrowsError(try repository.delete(id: builtIn.id)) {
            XCTAssertEqual($0 as? RoutineRepositoryError, .builtInRoutineIsReadOnly)
        }

        XCTAssertEqual(try base.list(), before)
        _ = container
    }

    func testUserRoutinesCanBeSavedUpdatedAndDeleted() throws {
        let (container, _, repository) = try makeRepository()
        let user = routine("User routine")
        try repository.save(user)
        var edited = user
        edited.name = "Edited routine"
        try repository.save(edited)

        XCTAssertEqual(try repository.list().first(where: { $0.id == user.id })?.name, "Edited routine")
        try repository.delete(id: user.id)
        XCTAssertFalse(try repository.list().contains { $0.id == user.id })
        _ = container
    }

    func testDuplicateOfBuiltInSavesAnEditableCopy() throws {
        let (container, base, repository) = try makeRepository()
        let builtIn = try XCTUnwrap(BuiltInRoutines.all.first)

        let copy = try repository.duplicate(builtIn)

        XCTAssertEqual(copy.name, "Upper Body Copy")
        XCTAssertNotEqual(copy.id, builtIn.id)
        XCTAssertNotEqual(copy.items.map(\.id), builtIn.items.map(\.id))
        XCTAssertEqual(try base.list(), [copy])
        var edited = copy
        edited.name = "Upper Body Edited"
        try repository.save(edited)
        XCTAssertEqual(try base.list().first?.name, "Upper Body Edited")
        XCTAssertEqual(Array(try repository.list().suffix(BuiltInRoutines.all.count)), BuiltInRoutines.all)
        _ = container
    }

    func testStoredRowWithBuiltInIdIsShadowedByCatalogValue() throws {
        let (container, base, repository) = try makeRepository()
        let builtIn = try XCTUnwrap(BuiltInRoutines.all.first)
        var conflict = builtIn
        conflict.name = "Stored conflict"
        try base.save(conflict)

        XCTAssertEqual(try repository.list(), BuiltInRoutines.all)
        XCTAssertEqual(try repository.listWithUpdateDates().map(\.set), BuiltInRoutines.all)
        _ = container
    }

    private func makeRepository() throws -> (ModelContainer, SwiftDataRoutineRepository, BuiltInRoutineRepository) {
        let container = try AppModelContainer.make(inMemory: true)
        let base = SwiftDataRoutineRepository(context: container.mainContext)
        return (container, base, BuiltInRoutineRepository(base: base))
    }

    private func routine(_ name: String) -> SavedExerciseSet {
        SavedExerciseSet(name: name, items: [
            SavedExerciseSetItem(exerciseID: .shoulderPress, setCount: 1, targetRepMinimum: 8, targetRepMaximum: 8)
        ])
    }
}
