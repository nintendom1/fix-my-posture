import Foundation

/// Chooses the emotional mode for an observation from its kind, familiarity, trajectory, and recent tones.
enum PersonaToneSelector {
    /// The ordered tone preferences for an observation before repetition is considered.
    static func preferences(
        for observation: PersonaObservation,
        familiarity: PersonaFamiliarity,
        trajectory: PersonaTrajectory
    ) -> [PersonaTone] {
        let familyKind = observation.key.familyKind
        switch familyKind {
        case "achievement.pr.weight", "achievement.pr.reps":
            return familiarity >= .established ? [.smug, .competitive, .proud] : [.proud, .pleased]
        case "achievement.milestone":
            return [.proud, .pleased, .warm]
        case "lapse.skippedExercise":
            switch familiarity {
            case .longTerm, .established: return [.annoyed, .smug, .concerned]
            case .familiar: return [.concerned, .warm]
            case .new: return [.concerned]
            }
        case "lapse.neglectedRoutine":
            if familiarity >= .established {
                return trajectory == .declining ? [.disappointed, .concerned] : [.annoyed, .concerned]
            }
            return [.concerned]
        case "lapse.decliningWeeks":
            return familiarity == .longTerm ? [.disappointed, .concerned] : [.concerned]
        case "lapse.comeback":
            return familiarity == .new ? [.warm] : [.relieved, .warm]
        default:
            if observation.key.family == .pattern {
                if trajectory == .declining { return [.warm, .pleased] }
                return familiarity < .established ? [.pleased, .warm] : [.smug, .pleased]
            }
            if observation.key.family == .posture { return [.pleased, .warm] }
            return [.pleased]
        }
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
        let available = preferences(for: observation, familiarity: familiarity, trajectory: trajectory)
            .filter { familiarity >= .established || !$0.isNegative }
        guard let first = available.first else { return .pleased }

        let firstIsOnlyPreference = available.count == 1
        for preference in available {
            let isMostRecent = recentTones.first == preference
            let repeatCount = recentTones.filter { $0 == preference }.count
            guard (firstIsOnlyPreference || !isMostRecent), repeatCount <= policy.maximumRepeatsOfTone else {
                continue
            }
            return preference
        }
        return first
    }
}
