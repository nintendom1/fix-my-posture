import Foundation

/// How strongly a local notification may interrupt. Persona notifications never use Time Sensitive.
enum NotificationInterruption: String, Codable, Equatable {
    /// iOS `.active`: sound and banner. Used for HIGH salience and for reminders.
    case active
    /// iOS `.passive`: delivered quietly to Notification Center. Used for MEDIUM salience.
    case passive
}

/// One standalone persona notification for the scheduler. Foundation-only so the planner can build it.
struct PersonaNotificationRequest: Equatable {
    /// Every persona request starts with this prefix.
    static let identifierPrefix = "fixMyPosture.persona."
    /// Projected (dated, future) requests. Each reconciliation replaces all pending ones.
    static let projectedPrefix = identifierPrefix + "plan."
    /// Immediate requests for the current event (possibly deferred past quiet hours). Never replaced by reconciliation.
    static let immediatePrefix = identifierPrefix + "now."

    /// userInfo keys the notification delegate reads to record engagement.
    enum UserInfoKey {
        static let traceID = "persona.traceID"
        static let observationKey = "persona.observationKey"
    }

    enum Trigger: Equatable {
        /// Fire after a delay, such as right after a workout save.
        case after(seconds: Int)
        /// Fire at a local wall-clock time (no time zone), like reminder requests.
        case at(DateComponents)
    }

    let identifier: String
    let title: String
    let body: String
    let imageAssetName: String?
    let categoryIdentifier: String
    let interruption: NotificationInterruption
    let trigger: Trigger
    /// Persona trace keys plus, when the observation carries a suggestion, the `WorkoutReminderTarget.payload` keys.
    let userInfo: [String: String]

    var isProjected: Bool { identifier.hasPrefix(Self.projectedPrefix) }

    /// `fixMyPosture.persona.plan.2026-10-26.pattern.weekday.1.2026-W44` (projected) or
    /// `fixMyPosture.persona.now.2026-10-24.achievement.pr.weight.dumbbell_row.2026-10-24` (immediate).
    static func identifier(day: DateComponents, observationKey: String, projected: Bool) -> String {
        let date = String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
        return (projected ? projectedPrefix : immediatePrefix) + date + "." + observationKey
    }
}

/// How a persona observation rides on the workout acknowledgment that is about to fire.
enum PersonaFold: Equatable {
    /// Use the persona title, body, and art instead of the acknowledgment's (HIGH or MEDIUM).
    case replace(CharacterNotificationContent)
    /// Keep the acknowledgment and add this line to its body (LOW).
    case append(line: String)
}

/// What happens right now for the current event.
enum PersonaImmediate: Equatable {
    case fold(PersonaFold)
    case standalone(PersonaNotificationRequest)
    /// LOW salience with no acknowledgment: recorded for the debug page, nothing is sent.
    case inAppOnly
}

/// The planner's whole answer for one evaluation.
struct PersonaPlan: Equatable {
    /// The decision for the current event, or nil when nothing should happen now.
    let immediate: PersonaImmediate?
    /// Dated future standalone notifications. Each reconciliation replaces every pending persona request.
    let scheduled: [PersonaNotificationRequest]
    /// One trace per candidate considered: sent (immediate, folded, or scheduled) or suppressed with a reason.
    let traces: [PersonaDecisionTrace]

    static let empty = PersonaPlan(immediate: nil, scheduled: [], traces: [])
}
