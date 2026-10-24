import Foundation

/// Achievement observations. See the detector table in docs/persona.md and PersonaPolicy for thresholds.
enum AchievementDetector: PersonaDetecting {
    static func observations(
        _ context: PersonaContext,
        asOf: Date,
        projected: Bool,
        policy: PersonaPolicy
    ) -> [PersonaObservation] {
        guard !projected,
              let trigger = PersonaDetectorSupport.freshTriggerRecord(in: context, asOf: asOf, policy: policy) else {
            return []
        }

        let records = PersonaDetectorSupport.records(context.records, through: asOf)
        let earlierRecords = records.filter { $0.endedAt < trigger.endedAt }
        var observations: [PersonaObservation] = []
        let weightPRs = weightPersonalRecords(
            trigger: trigger,
            earlierRecords: earlierRecords,
            context: context,
            policy: policy
        )
        observations.append(contentsOf: weightPRs.observations)
        observations.append(contentsOf: repPersonalRecords(
            trigger: trigger,
            earlierRecords: earlierRecords,
            suppressedExercises: weightPRs.exerciseIDs,
            context: context,
            policy: policy
        ))
        observations.append(contentsOf: milestone(
            trigger: trigger,
            records: records,
            policy: policy
        ))
        return PersonaDetectorSupport.ordered(observations)
    }

    private struct WeightedSet {
        let set: RecordedSet
        let kilograms: Double
    }

    private struct WeightPRResult {
        let observations: [PersonaObservation]
        let exerciseIDs: Set<ExerciseID>
    }

    private static func weightPersonalRecords(
        trigger: WorkoutRecord,
        earlierRecords: [WorkoutRecord],
        context: PersonaContext,
        policy: PersonaPolicy
    ) -> WeightPRResult {
        let exerciseIDs = Set(trigger.entries.map(\.exerciseID))
        var observations: [PersonaObservation] = []
        var prIDs = Set<ExerciseID>()
        let period = PersonaDetectorSupport.dayKey(trigger.endedAt, calendar: context.calendar)

        for exerciseID in exerciseIDs.sorted(by: { $0.rawValue < $1.rawValue }) {
            let triggerEntries = trigger.entries.filter { $0.exerciseID == exerciseID }
            let currentSets = triggerEntries.flatMap { comparableSets($0.sets) }
            guard let currentBest = best(currentSets) else { continue }

            var priorSets: [WeightedSet] = []
            var priorSessionCount = 0
            for record in earlierRecords {
                let sets = record.entries
                    .filter { $0.exerciseID == exerciseID }
                    .flatMap { comparableSets($0.sets) }
                if !sets.isEmpty {
                    priorSessionCount += 1
                    priorSets.append(contentsOf: sets)
                }
            }
            guard priorSessionCount >= policy.prMinimumPriorSessions,
                  let priorBest = best(priorSets),
                  currentBest.kilograms > priorBest.kilograms + 0.01 else {
                continue
            }

            let value = currentBest.set.weight?.label ?? ""
            let previousValue = priorBest.set.weight?.label ?? ""
            let highThreshold = (1 + policy.highWeightPRFraction) * priorBest.kilograms
            let salience: PersonaSalience = currentBest.kilograms >= highThreshold ? .high : .medium
            let evidenceStrength = salience == .high ? 5 : 4
            let entry = triggerEntries[0]
            observations.append(PersonaObservation(
                key: PersonaObservationKey(
                    family: .achievement,
                    kind: "pr.weight",
                    subject: exerciseID.rawValue,
                    period: period
                ),
                salience: salience,
                evidence: PersonaEvidence(
                    strength: evidenceStrength,
                    lines: ["New best \(value)", "Previous best \(previousValue)"]
                ),
                contentKey: "achievement.pr.weight",
                values: [
                    "exercise": PersonaDetectorSupport.exerciseName(exerciseID, entry: entry, context: context),
                    "value": value
                ],
                relatedWorkoutID: trigger.id,
                relatedExerciseID: exerciseID
            ))
            prIDs.insert(exerciseID)
        }
        return WeightPRResult(observations: observations, exerciseIDs: prIDs)
    }

    private static func repPersonalRecords(
        trigger: WorkoutRecord,
        earlierRecords: [WorkoutRecord],
        suppressedExercises: Set<ExerciseID>,
        context: PersonaContext,
        policy: PersonaPolicy
    ) -> [PersonaObservation] {
        let exerciseIDs = Set(trigger.entries.map(\.exerciseID)).subtracting(suppressedExercises)
        let period = PersonaDetectorSupport.dayKey(trigger.endedAt, calendar: context.calendar)
        var observations: [PersonaObservation] = []

        for exerciseID in exerciseIDs.sorted(by: { $0.rawValue < $1.rawValue }) {
            let triggerEntries = trigger.entries.filter { $0.exerciseID == exerciseID }
            // Sessions where the exercise was actually done; a skipped appearance has no sets and does not count.
            let sessions = earlierRecords.filter { record in
                record.entries.contains { $0.exerciseID == exerciseID && !$0.sets.isEmpty }
            }
            // A deload below the lightest weight ever used for this exercise is not a rep record.
            let lightestPriorKilograms = sessions.flatMap(\.entries)
                .filter { $0.exerciseID == exerciseID }
                .flatMap(\.sets)
                .compactMap { PersonaDetectorSupport.kilograms($0.weight) }
                .min()
            guard sessions.count >= policy.prMinimumPriorSessions else { continue }

            var bestGain: Int?
            var bestSet: RecordedSet?
            var previousBestReps = 0
            for entry in triggerEntries {
                for set in entry.sets {
                    guard let currentKilograms = repClassWeight(set.weight) else {
                        if set.weight != nil { continue }
                        let priorReps = sessions.flatMap { $0.entries }
                            .filter { $0.exerciseID == exerciseID }
                            .flatMap(\.sets)
                            .filter { $0.weight == nil }
                            .map(\.reps)
                        consider(
                            set,
                            priorReps: priorReps,
                            bestGain: &bestGain,
                            bestSet: &bestSet,
                            previousBestReps: &previousBestReps
                        )
                        continue
                    }

                    if let lightestPriorKilograms, currentKilograms + 0.01 < lightestPriorKilograms { continue }
                    let priorReps = sessions.flatMap { $0.entries }
                        .filter { $0.exerciseID == exerciseID }
                        .flatMap(\.sets)
                        .compactMap { priorSet -> Int? in
                            guard let priorWeight = PersonaDetectorSupport.kilograms(priorSet.weight),
                                  priorWeight + 0.01 >= currentKilograms else {
                                return nil
                            }
                            return priorSet.reps
                        }
                    consider(
                        set,
                        priorReps: priorReps,
                        bestGain: &bestGain,
                        bestSet: &bestSet,
                        previousBestReps: &previousBestReps
                    )
                }
            }

            guard let gain = bestGain, let set = bestSet, gain > 0,
                  let entry = triggerEntries.first else { continue }
            let value = PersonaDetectorSupport.weightLabel(set.weight)
            let salience: PersonaSalience = gain >= policy.highRepPRIncrease ? .high : .medium
            observations.append(PersonaObservation(
                key: PersonaObservationKey(
                    family: .achievement,
                    kind: "pr.reps",
                    subject: exerciseID.rawValue,
                    period: period
                ),
                salience: salience,
                evidence: PersonaEvidence(
                    strength: salience == .high ? 5 : 3,
                    lines: ["New best \(set.reps) reps at \(value)", "Previous best \(previousBestReps) reps"]
                ),
                contentKey: "achievement.pr.reps",
                values: [
                    "exercise": PersonaDetectorSupport.exerciseName(exerciseID, entry: entry, context: context),
                    "count": String(set.reps),
                    "value": value
                ],
                relatedWorkoutID: trigger.id,
                relatedExerciseID: exerciseID
            ))
        }
        return observations
    }

    private static func repClassWeight(_ weight: WorkoutWeight?) -> Double? {
        guard let weight else { return nil }
        return PersonaDetectorSupport.kilograms(weight)
    }

    private static func consider(
        _ set: RecordedSet,
        priorReps: [Int],
        bestGain: inout Int?,
        bestSet: inout RecordedSet?,
        previousBestReps: inout Int
    ) {
        guard let priorBest = priorReps.max(), set.reps > priorBest else { return }
        let gain = set.reps - priorBest
        guard bestGain.map({ gain > $0 }) ?? true else { return }
        bestGain = gain
        bestSet = set
        previousBestReps = priorBest
    }

    private static func comparableSets(_ sets: [RecordedSet]) -> [WeightedSet] {
        sets.compactMap { set in
            guard let kilograms = PersonaDetectorSupport.kilograms(set.weight) else { return nil }
            return WeightedSet(set: set, kilograms: kilograms)
        }
    }

    private static func best(_ sets: [WeightedSet]) -> WeightedSet? {
        sets.sorted {
            if $0.kilograms != $1.kilograms { return $0.kilograms > $1.kilograms }
            return ($0.set.weight?.label ?? "") < ($1.set.weight?.label ?? "")
        }.first
    }

    private static func milestone(
        trigger: WorkoutRecord,
        records: [WorkoutRecord],
        policy: PersonaPolicy
    ) -> [PersonaObservation] {
        let count = records.filter { $0.endedAt <= trigger.endedAt }.count
        guard policy.isWorkoutMilestone(count) else { return [] }
        let salience: PersonaSalience = count >= policy.highSalienceMilestone ? .high : .medium
        return [PersonaObservation(
            key: PersonaObservationKey(
                family: .achievement,
                kind: "milestone",
                subject: "workouts",
                period: String(count)
            ),
            salience: salience,
            evidence: PersonaEvidence(
                strength: salience == .high ? 5 : 4,
                lines: ["Workout \(count) saved"]
            ),
            contentKey: "achievement.milestone",
            values: ["count": String(count)],
            relatedWorkoutID: trigger.id
        )]
    }
}
