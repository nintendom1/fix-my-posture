import Foundation

/// Builds the one snapshot shared by the debug view and developer export.
struct AdaptiveSnapshotBuilder {
    let catalog: ProgressionCatalog
    let builtExerciseIDs: Set<String>
    let parameters: PolicyParameters
    let calendar: Calendar

    func snapshot(facts: AdaptiveFacts, asOf now: Date, appVersion: String) -> AdaptiveSnapshot {
        let profile = AdaptiveReplay.profile(facts: facts, catalog: catalog, builtExerciseIDs: builtExerciseIDs,
                                             parameters: parameters, calendar: calendar)
        let summaries = catalog.families.compactMap { family -> FamilySummary? in
            let state = profile.state(family.id)
            let evidence = facts.evidence.filter { $0.family == family.id }
            guard state != nil || !evidence.isEmpty else { return nil }

            let transitions = profile.transitions.filter { $0.family == family.id }
            let latestRationale = transitions.last(where: { $0.kind != .recordOnly })?.rationale.summary
            let recentEvidence = evidence
                .sorted(by: Self.newestEvidenceFirst)
                .prefix(AdaptiveSnapshot.recentEvidenceLimit)
                .map { evidence in
                    let transition = transitions.last { $0.id == evidence.id }
                    return EvidenceSummary(id: evidence.id, recordedAt: evidence.recordedAt, source: evidence.source,
                                           variant: evidence.variant, prescribed: evidence.prescribed,
                                           confirmed: evidence.confirmed, confirmation: evidence.confirmation,
                                           trackerStatus: evidence.tracker.status,
                                           trackerObserved: evidence.tracker.observed,
                                           rejectionReasons: evidence.tracker.rejectionReasons,
                                           effort: evidence.effort, midSetTooHard: evidence.midSetTooHard,
                                           bonus: evidence.bonus, completion: evidence.completion,
                                           decision: transition?.kind, codes: transition?.rationale.codes ?? [],
                                           summary: transition?.rationale.summary)
                }

            var effort = EffortCounts()
            var bonus = BonusCounts()
            for item in evidence {
                switch item.effort {
                case .tooHard: effort.tooHard += 1
                case .okay: effort.okay += 1
                case .easy: effort.easy += 1
                case nil: break
                }
                if let bonusRecord = item.bonus {
                    bonus.offered += 1
                    if bonusRecord.accepted { bonus.accepted += 1 }
                    else { bonus.declined += 1 }
                }
            }

            let sources = EvidenceSource.allCases.compactMap { source -> SourceCount? in
                let count = evidence.lazy.filter { $0.source == source }.count
                return count > 0 ? SourceCount(source: source, count: count) : nil
            }

            return FamilySummary(family: family.id, debugName: family.debugName,
                                 isActive: profile.activeFamilies.contains(family.id),
                                 current: state?.current,
                                 confidence: profile.confidence(of: family.id, asOf: now, parameters: parameters),
                                 lastPerformedAt: state?.lastPerformedAt, lastChangedAt: state?.lastChangedAt,
                                 latestRationale: latestRationale, recentEvidence: Array(recentEvidence),
                                 effort: effort, bonus: bonus,
                                 trackingIssues: evidence.filter { $0.tracker.status == .lost || $0.tracker.status == .lowConfidence }.count,
                                 sources: sources)
        }
        let availability = Availability(builtExerciseIDs: builtExerciseIDs, equipment: Set(profile.equipment))
        let today = AdaptiveReplay.todaySession(profile: profile, facts: facts, catalog: catalog,
                                                builtExerciseIDs: builtExerciseIDs, parameters: parameters,
                                                calendar: calendar, asOf: now)
        return AdaptiveSnapshot(generatedAt: now, appVersion: appVersion, timeZone: calendar.timeZone.identifier,
                                policyVersion: profile.policyVersion, parameters: parameters, catalog: catalog,
                                availability: availability, today: today, families: summaries, profile: profile,
                                events: AdaptiveReplay.events(facts: facts, profile: profile),
                                facts: facts)
    }

    private static func newestEvidenceFirst(_ lhs: AdaptiveEvidence, _ rhs: AdaptiveEvidence) -> Bool {
        if lhs.recordedAt != rhs.recordedAt { return lhs.recordedAt > rhs.recordedAt }
        return lhs.id.uuidString > rhs.id.uuidString
    }
}
