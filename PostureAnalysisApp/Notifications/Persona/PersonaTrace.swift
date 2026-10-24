import Foundation

/// A structured record of one decision, stored when it is made so the debug page never recomputes the
/// explanation later. Codable so it can be persisted and, later, charted.
struct PersonaDecisionTrace: Codable, Equatable, Identifiable {
    enum Outcome: Codable, Equatable {
        /// Scheduled or folded. `fireDate` is when iOS delivers it; `identifier` is the request identifier.
        case sent(fireDate: Date, identifier: String?)
        case suppressed(PersonaSuppressionReason)
    }

    let id: UUID
    /// Groups every candidate considered in one evaluation, so the detail view can list the others.
    let decisionID: UUID
    let decidedAt: Date
    let observation: PersonaObservation
    /// Salience after any similar-message or cooling downgrade.
    let salience: PersonaSalience
    let delivery: PersonaDelivery
    let tone: PersonaTone?
    let familiarity: PersonaFamiliarity
    let trajectory: PersonaTrajectory
    /// `contentKey#t<titleIndex>b<bodyIndex>[o<opener>][c<closer>|i<intro>]`, from the composer.
    let templateID: String?
    let title: String?
    let body: String?
    /// Standalone persona notifications already fired or planned for that day, before this one.
    let standaloneCountToday: Int
    let quietDeferred: Bool
    let cooling: PersonaCoolingLevel
    /// Fired messages of the same family and kind within the similar window.
    let recentSimilarCount: Int
    /// A one-sentence human explanation, such as "High-salience PR beat a pattern candidate; cap 0/2 today."
    let whyThisWon: String
    let outcome: Outcome

    var family: ObservationFamily { observation.family }

    var fireDate: Date? {
        if case .sent(let date, _) = outcome { return date }
        return nil
    }

    var identifier: String? {
        if case .sent(_, let identifier) = outcome { return identifier }
        return nil
    }

    /// A projected request that the next reconciliation replaces while it is still pending.
    var isProjected: Bool { identifier?.hasPrefix(PersonaNotificationRequest.projectedPrefix) ?? false }

    var suppressionReason: PersonaSuppressionReason? {
        if case .suppressed(let reason) = outcome { return reason }
        return nil
    }

    /// Sent and already delivered by `date`.
    func isFired(asOf date: Date) -> Bool {
        guard let fireDate else { return false }
        return fireDate <= date
    }

    /// Sent but still waiting in iOS at `date`.
    func isPending(asOf date: Date) -> Bool {
        guard let fireDate else { return false }
        return fireDate > date
    }
}

/// Everything the persona remembers that cannot be rebuilt from workout and posture history.
struct PersonaTraceState: Codable, Equatable {
    /// Every pending sent trace plus the newest fired ones (up to `PersonaPolicy.sentTraceLimit`), newest first.
    var sent: [PersonaDecisionTrace]
    /// Newest suppressed decisions, one per observation key, up to `PersonaPolicy.suppressedTraceLimit`, newest first.
    var suppressed: [PersonaDecisionTrace]
    /// Newest taps and dismissals, up to `PersonaPolicy.engagementLimit`, newest first.
    var engagement: [PersonaEngagementEvent]

    init(sent: [PersonaDecisionTrace] = [], suppressed: [PersonaDecisionTrace] = [], engagement: [PersonaEngagementEvent] = []) {
        self.sent = sent
        self.suppressed = suppressed
        self.engagement = engagement
    }

    static let empty = PersonaTraceState()

    /// Fired sent traces at `date`, newest first.
    func fired(asOf date: Date) -> [PersonaDecisionTrace] {
        // Implemented by P2.
        []
    }

    /// Sent traces that will not be replaced at `date`: fired ones plus pending immediate and folded ones. Used for the
    /// daily cap and for not repeating an observation key.
    func committed(asOf date: Date) -> [PersonaDecisionTrace] {
        // Implemented by P2.
        []
    }

    /// Tones of the newest fired traces, newest first, at most `limit`.
    func recentTones(asOf date: Date, limit: Int) -> [PersonaTone] {
        // Implemented by P2.
        []
    }

    /// Drops projected sent traces still pending at `now` (their requests are being replaced; immediate and folded
    /// traces stay), then adds `traces`:
    /// sent outcomes go to `sent`, suppressed outcomes to `suppressed` (replacing an older entry with the same
    /// observation key). Trims both lists to the policy limits, keeping every pending sent trace.
    mutating func replacePending(with traces: [PersonaDecisionTrace], now: Date, policy: PersonaPolicy = .standard) {
        // Implemented by P2.
    }

    /// Adds an engagement event, newest first, trimmed to the policy limit.
    mutating func record(_ event: PersonaEngagementEvent, policy: PersonaPolicy = .standard) {
        // Implemented by P2.
    }

    /// Forgets everything (Reset Persona).
    mutating func reset() {
        self = .empty
    }
}

/// Persists `PersonaTraceState`. The file store is the app's; tests use an in-memory fake.
protocol PersonaTraceStoring: AnyObject {
    func load() -> PersonaTraceState
    func save(_ state: PersonaTraceState)
}

/// Decides when not to interrupt. v1 uses fixed hours; a future explicit quiet-hours source plugs in here
/// without touching detectors or the planner.
protocol QuietHoursProviding {
    /// The quiet interval containing `date`, or nil when `date` is not in quiet hours.
    func quietInterval(containing date: Date, calendar: Calendar) -> DateInterval?
    /// A short description for the debug page, such as "22:00–08:00".
    var summary: String { get }
}

/// Quiet from `startHour` to `endHour` local time, crossing midnight when start is later than end.
struct FixedQuietHours: QuietHoursProviding, Equatable {
    var startHour: Int
    var endHour: Int

    init(startHour: Int = PersonaPolicy.standard.quietStartHour, endHour: Int = PersonaPolicy.standard.quietEndHour) {
        self.startHour = startHour
        self.endHour = endHour
    }

    var summary: String { String(format: "%02d:00–%02d:00", startHour, endHour) }

    func quietInterval(containing date: Date, calendar: Calendar) -> DateInterval? {
        // Implemented by P2.
        nil
    }
}
