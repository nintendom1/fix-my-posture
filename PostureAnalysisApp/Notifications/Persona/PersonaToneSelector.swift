import Foundation

/// Chooses the emotional mode for an observation from its kind, familiarity, trajectory, and recent tones.
enum PersonaToneSelector {
    /// The ordered tone preferences for an observation before repetition is considered.
    static func preferences(
        for observation: PersonaObservation,
        familiarity: PersonaFamiliarity,
        trajectory: PersonaTrajectory
    ) -> [PersonaTone] {
        // Implemented by P2.
        [.pleased]
    }

    /// The first preference that is not the most recent tone (when any alternative exists) and appears at most
    /// `policy.maximumRepeatsOfTone` times among `recentTones`; otherwise the first preference. Never returns a
    /// negative tone below established familiarity.
    static func tone(
        for observation: PersonaObservation,
        familiarity: PersonaFamiliarity,
        trajectory: PersonaTrajectory,
        recentTones: [PersonaTone],
        policy: PersonaPolicy = .standard
    ) -> PersonaTone {
        // Implemented by P2.
        .pleased
    }
}
