import Foundation

/// The single pure decision function for Extra Personable. Given a context it returns what to do now and
/// which persona notifications to schedule for the coming days, plus a trace for every candidate.
/// See docs/persona.md and the plan for the full algorithm.
enum PersonaPlanner {
    typealias Detect = (_ context: PersonaContext, _ asOf: Date, _ projected: Bool) -> [PersonaObservation]

    static func plan(
        context: PersonaContext,
        quietHours: any QuietHoursProviding,
        catalog: PersonaContentCatalog,
        policy: PersonaPolicy = .standard,
        detect: Detect? = nil
    ) -> PersonaPlan {
        // Implemented by P2. `detect` defaults to `PersonaDetectors.observations(_:asOf:projected:policy:)`.
        .empty
    }
}
