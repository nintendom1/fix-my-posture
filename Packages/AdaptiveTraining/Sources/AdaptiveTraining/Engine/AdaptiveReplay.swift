import Foundation

/// The pure core of the engine: facts in, interpretation out. `AdaptiveTrainingEngine` uses it with stored facts;
/// tests and the `adaptive-replay` tool use it with any facts, including a candidate `PolicyParameters`.
public enum AdaptiveReplay {
    /// Rebuilds the profile by replaying every fact in order under policy V1. Deterministic: the result depends
    /// only on the arguments (the calendar decides what "a different day" means).
    public static func profile(facts: AdaptiveFacts, catalog: ProgressionCatalog = .v1,
                               builtExerciseIDs: Set<String>, parameters: PolicyParameters = .standard,
                               calendar: Calendar) -> AdaptiveProfile {
        AdaptiveProjector(catalog: catalog, builtExerciseIDs: builtExerciseIDs, parameters: parameters,
                          calendar: calendar).replay(facts)
    }

    /// Every semantic event the facts produced, oldest first.
    public static func events(facts: AdaptiveFacts, profile: AdaptiveProfile) -> [AdaptiveEvent] {
        AdaptiveEventDeriver.events(facts: facts, profile: profile)
    }

    /// What Today's Session should be as of `now`.
    public static func todaySession(profile: AdaptiveProfile, facts: AdaptiveFacts,
                                    catalog: ProgressionCatalog = .v1, builtExerciseIDs: Set<String>,
                                    parameters: PolicyParameters = .standard, calendar: Calendar, asOf now: Date,
                                    context: SessionContext = .normal) -> TodaySessionStatus {
        TodaySessionPlanner(catalog: catalog, builtExerciseIDs: builtExerciseIDs, parameters: parameters,
                            calendar: calendar).status(profile: profile, facts: facts, asOf: now, context: context)
    }

    /// Where policy V1's Too Hard rule would go from `item`'s rung and dose, given the profile's availability: the
    /// easier version to offer mid-item. Nil when `item` isn't a main item of an active family, is already at the
    /// floor minimum, or nothing easier is available.
    public static func easierSwap(for item: PrescriptionItem, profile: AdaptiveProfile,
                                  catalog: ProgressionCatalog = .v1, builtExerciseIDs: Set<String>,
                                  parameters: PolicyParameters = .standard, calendar: Calendar,
                                  asOf now: Date) -> RungDose? {
        guard profile.activeFamilies.contains(item.family), let state = profile.state(item.family) else { return nil }
        let availability = Availability(builtExerciseIDs: builtExerciseIDs, equipment: Set(profile.equipment))
        return RecommendationPolicyV1(catalog: catalog, parameters: parameters, calendar: calendar)
            .easierSwapTarget(for: item, state: state, availability: availability, at: now)
    }

    /// The debug view's and the export's single source, as of `now`.
    public static func snapshot(facts: AdaptiveFacts, catalog: ProgressionCatalog = .v1,
                                builtExerciseIDs: Set<String>, parameters: PolicyParameters = .standard,
                                calendar: Calendar, asOf now: Date, appVersion: String) -> AdaptiveSnapshot {
        AdaptiveSnapshotBuilder(catalog: catalog, builtExerciseIDs: builtExerciseIDs, parameters: parameters,
                                calendar: calendar).snapshot(facts: facts, asOf: now, appVersion: appVersion)
    }
}
