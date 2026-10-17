import Foundation

/// Chooses the next Saved Set without depending on view state or persistence APIs.
enum RoutineRotation {
    static func upNext(
        routines: [SavedExerciseSetRecord],
        records: [WorkoutRecord],
        override: UUID?
    ) -> SavedExerciseSet? {
        if let override, let selected = routines.first(where: { $0.set.id == override }) {
            return selected.set
        }

        let neverDone = routines
            .filter { lastDone(routine: $0.set, records: records) == nil }
            .sorted(by: creationOrder)
        if let first = neverDone.first { return first.set }

        return routines.min { lhs, rhs in
            let lhsDate = lastDone(routine: lhs.set, records: records) ?? .distantFuture
            let rhsDate = lastDone(routine: rhs.set, records: records) ?? .distantFuture
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return creationOrder(lhs, rhs)
        }?.set
    }

    /// A stable plan identifier takes precedence. Name matching is reserved for legacy records
    /// that predate plan IDs, so a renamed or duplicated routine cannot claim another plan's history.
    static func lastDone(routine: SavedExerciseSet, records: [WorkoutRecord]) -> Date? {
        records.lazy
            .filter { record in
                if record.planID == routine.id { return true }
                return record.planID == nil && record.planName == routine.name
            }
            .map(\.endedAt)
            .max()
    }

    private static func creationOrder(_ lhs: SavedExerciseSetRecord, _ rhs: SavedExerciseSetRecord) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.set.id.uuidString < rhs.set.id.uuidString
    }
}
