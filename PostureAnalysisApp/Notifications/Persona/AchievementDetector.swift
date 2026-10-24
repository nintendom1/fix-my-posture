import Foundation

/// Achievement observations. See the detector table in docs/persona.md and PersonaPolicy for thresholds.
enum AchievementDetector: PersonaDetecting {
    static func observations(
        _ context: PersonaContext,
        asOf: Date,
        projected: Bool,
        policy: PersonaPolicy
    ) -> [PersonaObservation] {
        // Implemented by P1.
        []
    }
}
