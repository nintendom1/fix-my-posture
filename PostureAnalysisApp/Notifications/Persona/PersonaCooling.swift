import Foundation

/// Turns notification engagement into a frequency signal. Never affects warmth or copy, and never produces
/// a message about being ignored.
enum PersonaCooling {
    /// Strong: at least `strongCoolingDismissals` dismissals among the last `coolingLookback` fired messages, or the
    /// last `strongCoolingUnanswered` fired messages all went unanswered for `noResponseHours`. Mild: at least
    /// `mildCoolingDismissals` dismissals and no taps among the lookback. Engagement and fired messages older than
    /// `coolingDecayDays` are ignored. A tap on the newest fired message clears cooling.
    static func level(
        engagement: [PersonaEngagementEvent],
        sent: [PersonaDecisionTrace],
        now: Date,
        policy: PersonaPolicy = .standard
    ) -> PersonaCoolingLevel {
        // Implemented by P2.
        .none
    }

    /// Applies cooling to a salience. None: unchanged. Mild: medium becomes low. Strong: only high achievement and
    /// high `lapse.comeback` observations survive unchanged; everything else returns nil (suppressed as `.cooling`).
    static func adjusted(
        _ salience: PersonaSalience,
        for observation: PersonaObservation,
        level: PersonaCoolingLevel
    ) -> PersonaSalience? {
        // Implemented by P2.
        salience
    }
}
