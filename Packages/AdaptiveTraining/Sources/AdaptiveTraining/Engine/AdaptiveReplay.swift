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

    /// The debug view's and the export's single source, as of `now`.
    public static func snapshot(facts: AdaptiveFacts, catalog: ProgressionCatalog = .v1,
                                builtExerciseIDs: Set<String>, parameters: PolicyParameters = .standard,
                                calendar: Calendar, asOf now: Date, appVersion: String) -> AdaptiveSnapshot {
        AdaptiveSnapshotBuilder(catalog: catalog, builtExerciseIDs: builtExerciseIDs, parameters: parameters,
                                calendar: calendar).snapshot(facts: facts, asOf: now, appVersion: appVersion)
    }
}
