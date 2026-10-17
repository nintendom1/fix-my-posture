import Foundation
import Observation

@MainActor
protocol RoutineEditorViewModeling: AnyObject, Observable {
    var state: RoutineEditorState { get }
    func send(_ intent: RoutineEditorIntent)
}

@MainActor
@Observable
final class RoutineEditorViewModel: RoutineEditorViewModeling {
    private(set) var state: RoutineEditorState

    private let id: UUID
    private let routines: (any RoutineRepository)?
    private let exerciseCatalog: any ExerciseCatalogProviding
    private let router: AppRouter

    init(
        id: UUID?,
        routines: (any RoutineRepository)?,
        exerciseCatalog: any ExerciseCatalogProviding,
        router: AppRouter
    ) {
        self.routines = routines
        self.exerciseCatalog = exerciseCatalog
        self.router = router

        let existing = id.flatMap { targetID in
            (try? routines?.list().first { $0.id == targetID }) ?? nil
        }
        let routineID = existing?.id ?? id ?? UUID()
        self.id = routineID
        state = RoutineEditorState(
            name: existing?.name ?? "",
            items: existing?.items.map { item in
                Self.presentation(for: item, catalog: exerciseCatalog, expanded: false)
            } ?? [],
            isNew: existing == nil
        )
        refreshPickerExercises()
    }

    func send(_ intent: RoutineEditorIntent) {
        switch intent {
        case .nameChanged(let name):
            state.name = name
        case .addExercise(let exerciseID):
            addExercise(exerciseID)
        case .removeExercise(let itemID):
            state.items.removeAll { $0.id == itemID }
            refreshPickerExercises()
        case .toggleExpanded(let itemID):
            guard let index = state.items.firstIndex(where: { $0.id == itemID }) else { return }
            let willExpand = !state.items[index].isExpanded
            for itemIndex in state.items.indices { state.items[itemIndex].isExpanded = false }
            state.items[index].isExpanded = willExpand
        case .setCountChanged(let itemID, let value):
            updateItem(itemID) { $0.setCount = min(10, max(1, value)) }
        case .minimumRepsChanged(let itemID, let value):
            updateItem(itemID) { item in
                item.minimumReps = min(50, max(1, value))
                item.maximumReps = max(item.maximumReps, item.minimumReps)
            }
        case .maximumRepsChanged(let itemID, let value):
            updateItem(itemID) { item in
                item.maximumReps = min(50, max(1, value))
                item.minimumReps = min(item.minimumReps, item.maximumReps)
            }
        case .move(let from, let to):
            moveItem(from: from, to: to)
        case .moveUp(let itemID):
            moveItem(itemID, by: -1)
        case .moveDown(let itemID):
            moveItem(itemID, by: 1)
        case .presentPicker:
            state.isPickerPresented = true
            refreshPickerExercises()
        case .dismissPicker:
            state.isPickerPresented = false
        case .pickerSearchChanged(let text):
            state.pickerSearchText = text
            refreshPickerExercises()
        case .sortPicker(let option):
            state.pickerSort = option
            refreshPickerExercises()
        case .duplicate:
            guard !state.isNew, let routines else { return }
            do {
                _ = try routines.duplicate(currentDraft())
                state.isFinished = true
                popEditor()
            } catch {
                // Keep the draft open when duplication fails.
            }
        case .save:
            save()
        case .cancel:
            state.isPickerPresented = false
            state.showsDeleteConfirmation = false
            popEditor()
        case .requestDelete:
            guard !state.isNew else { return }
            state.showsDeleteConfirmation = true
        case .confirmDelete:
            guard state.showsDeleteConfirmation, !state.isNew else { return }
            do {
                try routines?.delete(id: id)
                state.showsDeleteConfirmation = false
                state.isFinished = true
                popToRoutinesRoot()
            } catch {
                // Keep the confirmation available so the user can try again.
            }
        case .cancelDelete:
            state.showsDeleteConfirmation = false
        }
    }

    private func addExercise(_ exerciseID: ExerciseID) {
        guard let exercise = exerciseCatalog.exercise(exerciseID) else { return }
        let item = SavedExerciseSetItem(exercise: exercise)
        state.items.append(Self.presentation(for: item, catalog: exerciseCatalog, expanded: false))
        refreshPickerExercises()
    }

    private func updateItem(_ id: UUID, update: (inout RoutineEditorItemState) -> Void) {
        guard let index = state.items.firstIndex(where: { $0.id == id }) else { return }
        update(&state.items[index])
        refreshPickerExercises()
    }

    private func moveItem(_ id: UUID, by offset: Int) {
        guard let index = state.items.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard state.items.indices.contains(target) else { return }
        state.items.swapAt(index, target)
    }

    private func moveItem(from source: Int, to destinationOffset: Int) {
        guard state.items.indices.contains(source),
              destinationOffset >= 0, destinationOffset <= state.items.count else { return }
        let item = state.items.remove(at: source)
        let adjustedDestination = destinationOffset > source ? destinationOffset - 1 : destinationOffset
        state.items.insert(item, at: min(state.items.count, max(0, adjustedDestination)))
    }

    private func save() {
        guard state.isSaveEnabled else { return }
        let saved = currentDraft()
        do {
            try routines?.save(saved)
            state.isFinished = true
            popEditor()
        } catch {
            // Keep the draft open when persistence fails.
        }
    }

    private func currentDraft() -> SavedExerciseSet {
        SavedExerciseSet(
            id: id,
            name: state.name.trimmingCharacters(in: .whitespacesAndNewlines),
            items: state.items.map {
                SavedExerciseSetItem(
                    id: $0.id,
                    exerciseID: $0.exerciseID,
                    setCount: $0.setCount,
                    targetRepMinimum: $0.minimumReps,
                    targetRepMaximum: $0.maximumReps
                )
            }
        )
    }

    private func refreshPickerExercises() {
        let counts = Dictionary(grouping: state.items, by: \.exerciseID).mapValues(\.count)
        let search = state.pickerSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let designOrder = ["shoulder_press", "hammer_curl", "triceps_extension", "dumbbell_row", "air_squat", "push_up"]
        let catalogItems = exerciseCatalog.all.enumerated().compactMap { index, exercise -> (Int, ExerciseDefinition, Int)? in
            let count = counts[exercise.id, default: 0]
            let presentation = exercise.presentation
            let searchable = ([presentation.shortName, exercise.displayName] + presentation.muscles)
                .joined(separator: " ")
            guard search.isEmpty || searchable.localizedCaseInsensitiveContains(search) else { return nil }
            return (index, exercise, count)
        }
        let sorted = catalogItems.sorted { left, right in
            switch state.pickerSort {
            case .inRoutine:
                if left.2 != right.2 { return left.2 > right.2 }
            case .mostReps:
                if left.1.targetReps.upperBound != right.1.targetReps.upperBound {
                    return left.1.targetReps.upperBound > right.1.targetReps.upperBound
                }
            case .fewestReps:
                if left.1.targetReps.lowerBound != right.1.targetReps.lowerBound {
                    return left.1.targetReps.lowerBound < right.1.targetReps.lowerBound
                }
            }
            let leftOrder = designOrder.firstIndex(of: left.1.id.rawValue) ?? (designOrder.count + left.0)
            let rightOrder = designOrder.firstIndex(of: right.1.id.rawValue) ?? (designOrder.count + right.0)
            return leftOrder < rightOrder
        }
        state.pickerExercises = sorted.map { _, exercise, count in
            let presentation = exercise.presentation
            return AddExercisePresentation(
                exerciseID: exercise.id,
                name: presentation.shortName,
                target: "\(exercise.sets) × \(exercise.targetLabel)",
                muscles: presentation.muscles.joined(separator: " · "),
                gradient: presentation.gradient,
                symbolName: presentation.symbolName,
                inRoutineCount: count
            )
        }
    }

    private func popEditor() {
        let path = router.path(for: .routines)
        if !path.isEmpty {
            router.setPath(Array(path.dropLast()), for: .routines)
        }
        router.selectedTab = .routines
    }

    private func popToRoutinesRoot() {
        router.setPath([], for: .routines)
        router.selectedTab = .routines
    }

    private static func presentation(
        for item: SavedExerciseSetItem,
        catalog: any ExerciseCatalogProviding,
        expanded: Bool
    ) -> RoutineEditorItemState {
        let exercise = catalog.exercise(item.exerciseID)
        return RoutineEditorItemState(
            id: item.id,
            exerciseID: item.exerciseID,
            name: exercise?.presentation.shortName ?? "Unavailable exercise",
            gradient: exercise?.presentation.gradient ?? ExerciseGradient(token: .press, stops: ["#7C4DFF", "#C04BD8"], angle: 135),
            symbolName: exercise?.presentation.symbolName ?? "dumbbell.fill",
            isAvailable: exercise != nil,
            isPerSide: exercise?.perSide ?? false,
            setCount: item.setCount,
            minimumReps: item.targetRepMinimum,
            maximumReps: item.targetRepMaximum,
            isExpanded: expanded
        )
    }
}
