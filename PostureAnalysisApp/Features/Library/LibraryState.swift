import Foundation

struct LibraryExerciseRow: Equatable, Identifiable {
    let id: ExerciseID
    let name: String
    let muscles: String
    let target: String
    let weight: String?
    let equipment: String
    let cameraSetup: String
    let gradient: ExerciseGradient
    let symbolName: String
}

struct LibraryExerciseGroup: Equatable, Identifiable {
    let title: String
    let exercises: [LibraryExerciseRow]

    var id: String { title }
}

struct LibraryEmptyState: Equatable {
    let title: String
    let message: String
    let actionTitle: String

    static let noMatches = LibraryEmptyState(
        title: "No exercises match",
        message: "Try a different search or clear your filters.",
        actionTitle: "Clear filters"
    )
}

struct LibraryState: Equatable {
    var groups: [LibraryExerciseGroup]
    var selectedFilter: ExerciseFilterChip
    var query: String
    let searchPlaceholder: String

    var emptyState: LibraryEmptyState? { groups.isEmpty ? .noMatches : nil }

    init(
        groups: [LibraryExerciseGroup] = [],
        selectedFilter: ExerciseFilterChip = .all,
        query: String = "",
        searchPlaceholder: String = "Search exercises"
    ) {
        self.groups = groups
        self.selectedFilter = selectedFilter
        self.query = query
        self.searchPlaceholder = searchPlaceholder
    }
}

enum LibraryIntent: Equatable {
    case appeared
    case back
    case exerciseSelected(ExerciseID)
    case filterSelected(ExerciseFilterChip)
    case queryChanged(String)
    case clearFilters
}
