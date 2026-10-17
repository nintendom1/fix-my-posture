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

enum LibraryFilter: String, CaseIterable, Equatable, Identifiable {
    case all
    case upperBody
    case lowerBody
    case bodyweight
    case dumbbells

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "All"
        case .upperBody: return "Upper body"
        case .lowerBody: return "Lower body"
        case .bodyweight: return "Bodyweight"
        case .dumbbells: return "Dumbbells"
        }
    }

    var anchorWidth: CGFloat {
        switch self {
        case .all: return 48
        case .upperBody: return 105.5
        case .lowerBody: return 106
        case .bodyweight: return 108.5
        case .dumbbells: return 101
        }
    }
}

struct LibraryState: Equatable {
    var groups: [LibraryExerciseGroup]
    var selectedFilter: LibraryFilter
    let searchPlaceholder: String
    let isSearchEnabled: Bool

    init(
        groups: [LibraryExerciseGroup] = [],
        selectedFilter: LibraryFilter = .all,
        searchPlaceholder: String = "Search exercises",
        isSearchEnabled: Bool = false
    ) {
        self.groups = groups
        self.selectedFilter = selectedFilter
        self.searchPlaceholder = searchPlaceholder
        self.isSearchEnabled = isSearchEnabled
    }
}

enum LibraryIntent: Equatable {
    case appeared
    case back
    case exerciseSelected(ExerciseID)
}
