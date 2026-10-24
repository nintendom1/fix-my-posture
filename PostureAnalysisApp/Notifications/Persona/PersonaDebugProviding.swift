import Foundation

/// A live snapshot of the persona's derived state for the developer debug page.
struct PersonaStatus: Equatable {
    /// The Extra Personable preference.
    let extraPersonableEnabled: Bool
    /// Extra Personable, reminders, and Character style are all on, so the persona can speak.
    let isActive: Bool
    let familiarity: PersonaFamiliarity
    let trajectory: PersonaTrajectory
    let cooling: PersonaCoolingLevel
    /// Standalone persona notifications fired today.
    let standaloneCountToday: Int
    let dailyCap: Int
    /// Pending persona notifications in iOS, per the trace store.
    let pendingCount: Int
    let quietHoursSummary: String
    let isQuietNow: Bool
    let personaResetDate: Date?

    static let inactive = PersonaStatus(
        extraPersonableEnabled: false, isActive: false, familiarity: .new, trajectory: .unknown, cooling: .none,
        standaloneCountToday: 0, dailyCap: PersonaPolicy.standard.dailyStandaloneCap, pendingCount: 0,
        quietHoursSummary: FixedQuietHours().summary, isQuietNow: false, personaResetDate: nil
    )
}

/// What the Persona Debug page needs from the app. `WorkoutReminderCoordinator` implements it; tests use a fake.
@MainActor
protocol PersonaDebugProviding: AnyObject {
    func personaStatus() -> PersonaStatus
    func personaTraceState() -> PersonaTraceState
    /// Re-runs reminder reconciliation, which re-evaluates the persona and replaces pending persona requests.
    func runPersonaDetectorsNow() async
    /// Reset Persona: sets the reset date to now, clears traces, engagement, and tones, keeps history and the setting.
    func resetPersona() async
}
