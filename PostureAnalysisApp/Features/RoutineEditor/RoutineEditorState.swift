import Foundation

struct RoutineEditorItemState: Equatable, Identifiable {
    let id: UUID
    let exerciseID: ExerciseID
    let name: String
    let gradient: ExerciseGradient
    let symbolName: String
    let isAvailable: Bool
    let isPerSide: Bool
    var sideLimb: ExerciseSideLimb = .arm
    var setCount: Int
    var minimumReps: Int
    var maximumReps: Int
    var isExpanded: Bool

    var setsAndRepsLabel: String {
        let reps = minimumReps == maximumReps ? "\(minimumReps)" : "\(minimumReps)–\(maximumReps)"
        return "\(setCount) × \(reps)"
    }

    var targetLabel: String {
        guard isPerSide else { return setsAndRepsLabel }
        return setsAndRepsLabel + (sideLimb == .leg ? " each leg" : " / side")
    }
}

struct AddExercisePresentation: Equatable, Identifiable {
    let exerciseID: ExerciseID
    let name: String
    let target: String
    let muscles: String
    let gradient: ExerciseGradient
    let symbolName: String
    let inRoutineCount: Int

    var id: ExerciseID { exerciseID }
}

enum AddExerciseSortOption: String, CaseIterable, Equatable, Identifiable {
    case inRoutine
    case mostReps
    case fewestReps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inRoutine: return "In routine"
        case .mostReps: return "Most reps"
        case .fewestReps: return "Fewest reps"
        }
    }
}

struct RoutineEditorState: Equatable {
    var name: String
    var items: [RoutineEditorItemState]
    var isNew: Bool
    var isPickerPresented: Bool
    var pickerSearchText: String
    var pickerSort: AddExerciseSortOption
    var pickerExercises: [AddExercisePresentation]
    var showsDeleteConfirmation: Bool
    var isFinished: Bool
    var estimatedMinutes: Int?

    var title: String { isNew ? "New Routine" : "Edit Routine" }
    var isSaveEnabled: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !items.isEmpty
    }
    var summary: String {
        guard !items.isEmpty else { return "No exercises yet" }
        let exerciseCount = items.count
        let setCount = items.reduce(0) { $0 + $1.setCount }
        let exerciseLabel = exerciseCount == 1 ? "1 exercise" : "\(exerciseCount) exercises"
        let setLabel = setCount == 1 ? "1 set" : "\(setCount) sets"
        return "\(exerciseLabel) · \(setLabel)"
    }
    var timeEstimateSummary: String {
        guard !items.isEmpty, let estimatedMinutes else { return "Add exercises to see the time" }
        return "About \(estimatedMinutes) min including rest"
    }

    init(
        name: String,
        items: [RoutineEditorItemState] = [],
        isNew: Bool,
        isPickerPresented: Bool = false,
        pickerSearchText: String = "",
        pickerSort: AddExerciseSortOption = .inRoutine,
        pickerExercises: [AddExercisePresentation] = [],
        showsDeleteConfirmation: Bool = false,
        isFinished: Bool = false,
        estimatedMinutes: Int? = nil
    ) {
        self.name = name
        self.items = items
        self.isNew = isNew
        self.isPickerPresented = isPickerPresented
        self.pickerSearchText = pickerSearchText
        self.pickerSort = pickerSort
        self.pickerExercises = pickerExercises
        self.showsDeleteConfirmation = showsDeleteConfirmation
        self.isFinished = isFinished
        self.estimatedMinutes = estimatedMinutes
    }
}

enum RoutineEditorIntent: Equatable {
    case nameChanged(String)
    case addExercise(ExerciseID)
    case removeExercise(UUID)
    case toggleExpanded(UUID)
    case setCountChanged(itemID: UUID, value: Int)
    case minimumRepsChanged(itemID: UUID, value: Int)
    case maximumRepsChanged(itemID: UUID, value: Int)
    case move(from: Int, to: Int)
    case moveUp(UUID)
    case moveDown(UUID)
    case presentPicker
    case dismissPicker
    case pickerSearchChanged(String)
    case sortPicker(AddExerciseSortOption)
    case duplicate
    case save
    case cancel
    case requestDelete
    case confirmDelete
    case cancelDelete
}
