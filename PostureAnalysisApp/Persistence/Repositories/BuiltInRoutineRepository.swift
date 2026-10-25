import Foundation

enum RoutineRepositoryError: Error, Equatable {
    case builtInRoutineIsReadOnly
}

/// Adds the read-only starter routines to the user's own routines. Saving or deleting a starter routine throws;
/// duplicating one saves an editable copy through the base repository.
@MainActor
final class BuiltInRoutineRepository: RoutineRepository {
    private let base: any RoutineRepository
    private let builtIns: [SavedExerciseSet]

    init(base: any RoutineRepository, builtIns: [SavedExerciseSet] = BuiltInRoutines.all) {
        self.base = base
        self.builtIns = builtIns
    }

    func list() throws -> [SavedExerciseSet] {
        let builtInIDs = Set(builtIns.map(\.id))
        let userRoutines = try base.list().filter { !builtInIDs.contains($0.id) }
        return userRoutines + builtIns
    }

    func listWithUpdateDates() throws -> [SavedExerciseSetRecord] {
        let builtInIDs = Set(builtIns.map(\.id))
        let userRoutines = try base.listWithUpdateDates().filter { !builtInIDs.contains($0.set.id) }
        let builtInRecords = builtIns.enumerated().map { index, set in
            let date = Date.distantPast.addingTimeInterval(TimeInterval(index))
            return SavedExerciseSetRecord(set: set, createdAt: date, updatedAt: date)
        }
        return userRoutines + builtInRecords
    }

    func save(_ set: SavedExerciseSet) throws {
        guard !isBuiltIn(id: set.id) else { throw RoutineRepositoryError.builtInRoutineIsReadOnly }
        try base.save(set)
    }

    func duplicate(_ set: SavedExerciseSet) throws -> SavedExerciseSet {
        if isBuiltIn(id: set.id) {
            let copy = set.duplicated()
            try base.save(copy)
            return copy
        }
        return try base.duplicate(set)
    }

    func delete(id: UUID) throws {
        guard !isBuiltIn(id: id) else { throw RoutineRepositoryError.builtInRoutineIsReadOnly }
        try base.delete(id: id)
    }

    private func isBuiltIn(id: UUID) -> Bool {
        builtIns.contains { $0.id == id }
    }
}
