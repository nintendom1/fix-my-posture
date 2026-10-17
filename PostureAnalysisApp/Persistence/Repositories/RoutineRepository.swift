import Foundation
import SwiftData

@MainActor
protocol RoutineRepository {
    func list() throws -> [SavedExerciseSet]
    func save(_ set: SavedExerciseSet) throws
    func duplicate(_ set: SavedExerciseSet) throws -> SavedExerciseSet
    func delete(id: UUID) throws
}

@MainActor
final class SwiftDataRoutineRepository: RoutineRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func list() throws -> [SavedExerciseSet] {
        do {
            let descriptor = FetchDescriptor<SavedExerciseSetEntity>(sortBy: [SortDescriptor(\.createdAt)])
            return try context.fetch(descriptor).map(\.value)
        } catch {
            PersistenceRepositoryLogging.failed("List Saved Sets", error: error)
            throw error
        }
    }

    func save(_ set: SavedExerciseSet) throws {
        do {
            if let entity = try context.fetch(FetchDescriptor<SavedExerciseSetEntity>()).first(where: { $0.id == set.id }) {
                entity.update(from: set)
            } else {
                context.insert(SavedExerciseSetEntity(set))
            }
            try context.save()
        } catch {
            PersistenceRepositoryLogging.failed("Save Saved Set", error: error)
            throw error
        }
    }

    func duplicate(_ set: SavedExerciseSet) throws -> SavedExerciseSet {
        let copy = set.duplicated()
        try save(copy)
        return copy
    }

    func delete(id: UUID) throws {
        do {
            guard let entity = try context.fetch(FetchDescriptor<SavedExerciseSetEntity>()).first(where: { $0.id == id }) else {
                return
            }
            context.delete(entity)
            try context.save()
        } catch {
            PersistenceRepositoryLogging.failed("Delete Saved Set", error: error)
            throw error
        }
    }
}
