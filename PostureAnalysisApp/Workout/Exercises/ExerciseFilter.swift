import Foundation

enum ExerciseFilterChip: String, CaseIterable, Equatable, Hashable, Identifiable {
    case all
    case upper
    case lower
    case bodyweight
    case dumbbells

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "All"
        case .upper: return "Upper body"
        case .lower: return "Lower body"
        case .bodyweight: return "Bodyweight"
        case .dumbbells: return "Dumbbells"
        }
    }
}

enum ExerciseFilter {
    static func apply(
        _ exercises: [ExerciseDefinition],
        chip: ExerciseFilterChip,
        query: String
    ) -> [ExerciseDefinition] {
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)

        return exercises.filter { exercise in
            guard matches(chip: chip, exercise: exercise) else { return false }
            guard !tokens.isEmpty else { return true }

            let presentation = exercise.presentation
            let searchableText = ([exercise.displayName, presentation.shortName]
                + presentation.muscles
                + [presentation.equipmentLine])
                .joined(separator: " ")

            return tokens.allSatisfy { token in
                searchableText.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    private static func matches(chip: ExerciseFilterChip, exercise: ExerciseDefinition) -> Bool {
        let group: ExerciseFilterGroup
        switch chip {
        case .all: return true
        case .upper: group = .upper
        case .lower: group = .lower
        case .bodyweight: group = .bodyweight
        case .dumbbells: group = .dumbbells
        }
        return exercise.presentation.filterGroups.contains(group)
    }
}
