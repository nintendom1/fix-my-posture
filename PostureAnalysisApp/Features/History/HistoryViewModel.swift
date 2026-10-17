import Foundation
import Observation

@MainActor
@Observable
final class HistoryViewModel {
    private(set) var state: HistoryState

    private let repository: (any WorkoutHistoryRepository)?
    let exerciseCatalog: any ExerciseCatalogProviding
    private let now: () -> Date
    private let calendar: Calendar

    init(
        repository: (any WorkoutHistoryRepository)?,
        exerciseCatalog: any ExerciseCatalogProviding = LiveExerciseCatalog(),
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.exerciseCatalog = exerciseCatalog
        self.now = now
        self.calendar = calendar
        state = HistoryState(groups: [])
        refresh()
    }

    func refresh() {
        let records = (try? repository?.list()) ?? []
        state = HistoryState(groups: HistoryWeekGrouping(records: records, now: now(), calendar: calendar).weeks)
    }

    func openRecord(id: UUID) -> WorkoutRecord? {
        state.groups.lazy.flatMap(\.records).first { $0.id == id }
    }

    func delete(recordID: UUID) {
        try? repository?.delete(id: recordID)
        refresh()
    }

    @discardableResult
    func updateWeight(
        recordID: UUID,
        entryID: UUID,
        setIndex: Int,
        weight: WorkoutWeight?,
        applyToLater: Bool
    ) -> WorkoutRecord? {
        guard var record = openRecord(id: recordID),
              let entryIndex = record.entries.firstIndex(where: { $0.id == entryID }),
              record.entries[entryIndex].sets.indices.contains(setIndex) else { return nil }

        for index in record.entries[entryIndex].sets.indices
        where index == setIndex || (applyToLater && index > setIndex) {
            record.entries[entryIndex].sets[index].weight = weight
        }
        try? repository?.updateWeights(for: record)
        refresh()
        return record
    }
}
