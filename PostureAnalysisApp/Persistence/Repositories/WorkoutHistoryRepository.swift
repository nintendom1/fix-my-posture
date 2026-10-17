import Foundation
import SwiftData

@MainActor
protocol WorkoutHistoryRepository {
    func list() throws -> [WorkoutRecord]
    func save(_ record: WorkoutRecord) throws
    func updateWeights(for record: WorkoutRecord) throws
    func delete(id: UUID) throws
}

@MainActor
final class SwiftDataWorkoutHistoryRepository: WorkoutHistoryRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func list() throws -> [WorkoutRecord] {
        do {
            let descriptor = FetchDescriptor<WorkoutRecordEntity>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
            return try context.fetch(descriptor).map(\.value)
        } catch {
            PersistenceRepositoryLogging.failed("List workout history", error: error)
            throw error
        }
    }

    func save(_ record: WorkoutRecord) throws {
        do {
            if let entity = try context.fetch(FetchDescriptor<WorkoutRecordEntity>()).first(where: { $0.id == record.id }) {
                entity.startedAt = record.startedAt
                entity.endedAt = record.endedAt
                entity.planID = record.planID
                entity.planName = record.planName
                entity.update(entries: record.entries)
            } else {
                context.insert(WorkoutRecordEntity(record))
            }
            try context.save()
        } catch {
            PersistenceRepositoryLogging.failed("Save workout history", error: error)
            throw error
        }
    }

    func updateWeights(for record: WorkoutRecord) throws {
        do {
            guard let entity = try context.fetch(FetchDescriptor<WorkoutRecordEntity>()).first(where: { $0.id == record.id }) else {
                return
            }
            entity.update(entries: record.entries)
            try context.save()
        } catch {
            PersistenceRepositoryLogging.failed("Update workout weights", error: error)
            throw error
        }
    }

    func delete(id: UUID) throws {
        do {
            guard let entity = try context.fetch(FetchDescriptor<WorkoutRecordEntity>()).first(where: { $0.id == id }) else {
                return
            }
            context.delete(entity)
            try context.save()
        } catch {
            PersistenceRepositoryLogging.failed("Delete workout history", error: error)
            throw error
        }
    }
}
