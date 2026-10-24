import Foundation

/// One family's detector. Detectors are pure: they read time only from `asOf` and `context`, never `Date()`.
///
/// - `projected == false`: evaluating the triggering event (a just-saved workout or the current moment). Kinds that
///   need a triggering record (PRs, milestones, comeback, skipped exercise, posture return) are allowed.
/// - `projected == true`: evaluating a future (or later-today) slot at `asOf`, reading history as it stands, so
///   future days project as misses. Only history-state kinds (weekday pattern nudges, neglected routine,
///   declining weeks) may be produced.
protocol PersonaDetecting {
    static func observations(
        _ context: PersonaContext,
        asOf: Date,
        projected: Bool,
        policy: PersonaPolicy
    ) -> [PersonaObservation]
}

/// The detector registry. Adding a family (for example `occasion` for holidays) means one new detector type,
/// its content keys in persona-content.json, and one line here.
enum PersonaDetectors {
    static let all: [any PersonaDetecting.Type] = [
        AchievementDetector.self,
        PatternDetector.self,
        LapseDetector.self,
        PostureDetector.self,
    ]

    /// Every detector's observations, in registry order. Does not rank or filter; the planner does.
    static func observations(
        _ context: PersonaContext,
        asOf: Date,
        projected: Bool,
        policy: PersonaPolicy = .standard
    ) -> [PersonaObservation] {
        // Implemented by P1 (may stay this simple).
        all.flatMap { $0.observations(context, asOf: asOf, projected: projected, policy: policy) }
    }
}
