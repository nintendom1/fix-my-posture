import Foundation

/// Turns notification engagement into a frequency signal. Never affects warmth or copy, and never produces
/// a message about being ignored.
enum PersonaCooling {
    /// Strong: at least `strongCoolingDismissals` dismissals among the last `coolingLookback` fired messages, or the
    /// last `strongCoolingUnanswered` fired messages all went unanswered for `noResponseHours`. Mild: at least
    /// `mildCoolingDismissals` dismissals and no taps among the lookback. Engagement and fired messages older than
    /// `coolingDecayDays` are ignored. A tap on the newest fired message clears cooling. Only standalone (active or
    /// passive) traces count, because folded messages cannot report engagement.
    static func level(
        engagement: [PersonaEngagementEvent],
        sent: [PersonaDecisionTrace],
        now: Date,
        policy: PersonaPolicy = .standard
    ) -> PersonaCoolingLevel {
        let cutoff = now.addingTimeInterval(-TimeInterval(policy.coolingDecayDays) * 86_400)
        // Only standalone persona notifications can report a tap or dismissal; folded messages ride on the
        // acknowledgment, so counting them would read as "ignored" and mute her for no reason.
        let recent = sent
            .filter { trace in
                guard trace.delivery.isStandalone, let fireDate = trace.fireDate else { return false }
                return fireDate >= cutoff && fireDate <= now
            }
            .sorted { lhs, rhs in
                guard let left = lhs.fireDate, let right = rhs.fireDate else { return false }
                if left != right { return left > right }
                return lhs.decidedAt > rhs.decidedAt
            }
            .prefix(max(0, policy.coolingLookback))
        let recentTraces = Array(recent)
        guard let newest = recentTraces.first else { return .none }

        let recentEngagement = engagement.filter { $0.date >= cutoff && $0.date <= now }
        let eventsByTraceID = Dictionary(grouping: recentEngagement, by: \.traceID)
        let newestEvents = eventsByTraceID[newest.id] ?? []
        if newestEvents.contains(where: { $0.kind == .tapped }) { return .none }

        let traceIDs = Set(recentTraces.map(\.id))
        let lookbackEvents = recentEngagement.filter { traceIDs.contains($0.traceID) }
        let dismissals = lookbackEvents.filter { $0.kind == .dismissed }.count
        let taps = lookbackEvents.filter { $0.kind == .tapped }.count
        if dismissals >= policy.strongCoolingDismissals { return .strong }

        let unansweredCount = max(0, policy.strongCoolingUnanswered)
        let unanswered = Array(recentTraces.prefix(unansweredCount))
        if unansweredCount > 0, unanswered.count == unansweredCount {
            let noResponseCutoff = now.addingTimeInterval(-TimeInterval(policy.noResponseHours) * 3_600)
            let allOldEnough = unanswered.allSatisfy { ($0.fireDate ?? now) < noResponseCutoff }
            let noneEngaged = unanswered.allSatisfy { (eventsByTraceID[$0.id] ?? []).isEmpty }
            if allOldEnough && noneEngaged { return .strong }
        }

        if dismissals >= policy.mildCoolingDismissals && taps == 0 { return .mild }
        return .none
    }

    /// Applies cooling to a salience. None: unchanged. Mild: medium becomes low. Strong: only high achievement and
    /// high `lapse.comeback` observations survive unchanged; everything else returns nil (suppressed as `.cooling`).
    static func adjusted(
        _ salience: PersonaSalience,
        for observation: PersonaObservation,
        level: PersonaCoolingLevel
    ) -> PersonaSalience? {
        switch level {
        case .none:
            return salience
        case .mild:
            return salience == .medium ? .low : salience
        case .strong:
            let mayKeepHigh = salience == .high
                && (observation.key.family == .achievement || observation.key.kind == "comeback")
            return mayKeepHigh ? .high : nil
        }
    }
}
