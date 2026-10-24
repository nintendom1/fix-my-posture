import Foundation

/// A composed persona message and the template choices that produced it (for the decision trace).
struct PersonaComposition: Equatable {
    let content: CharacterNotificationContent
    /// `contentKey#t<titleIndex>b<bodyIndex>` plus `o<index>` for an opener and `c<index>` or `i<index>` for a closer
    /// or intro fragment, such as `achievement.pr.weight#t0b1o2`.
    let templateID: String
}

/// Builds persona copy from structured facts: content key, tone, familiarity, token values, and a variant number.
/// No business logic lives in strings and no copy lives in Swift.
enum PersonaCopyComposer {
    /// Eligible titles and bodies are those whose tones include `tone` (or are untagged) and whose
    /// `minFamiliarity` is at or below `familiarity`. If none are eligible for `tone`, the entry's `defaultTone` is
    /// used. `variant` (any integer, wrapped) picks the title, the body, and the fragment pattern: `variant % 4` is
    /// none, opener, closer, or both, using only eligible fragments that keep the body within the length limit.
    /// When `intro` is true an intro fragment replaces the closer. Art is `catalog.art(for:tone:)` with the tone
    /// actually used. Lines whose tokens cannot be filled are skipped; nil when nothing can be composed.
    /// The result's `content.kind` is `.persona` and `content.scenarioID` is the content key.
    static func compose(
        catalog: PersonaContentCatalog,
        contentKey: String,
        tone: PersonaTone,
        familiarity: PersonaFamiliarity,
        values: [String: String],
        variant: Int,
        intro: Bool
    ) -> PersonaComposition? {
        // Implemented by P4.
        nil
    }

    /// How many distinct title × body combinations are eligible, for the developer preview's variant stepper.
    static func variantCount(
        catalog: PersonaContentCatalog,
        contentKey: String,
        tone: PersonaTone,
        familiarity: PersonaFamiliarity
    ) -> Int {
        // Implemented by P4.
        0
    }

    /// Longest composed body allowed, matching the scenario copy limit.
    static let maximumBodyLength = 110
}
