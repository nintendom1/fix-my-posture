import Foundation

/// Lapse observations. See the detector table in docs/persona.md and PersonaPolicy for thresholds.
enum LapseDetector: PersonaDetecting {
    static func observations(
        _ context: PersonaContext,
        asOf: Date,
        projected: Bool,
        policy: PersonaPolicy
    ) -> [PersonaObservation] {
        if projected {
            return PersonaDetectorSupport.ordered(
                neglectedRoutine(context: context, asOf: asOf, policy: policy)
                    + decliningWeeks(context: context, asOf: asOf, policy: policy)
            )
        }
        guard let trigger = PersonaDetectorSupport.freshTriggerRecord(in: context, asOf: asOf, policy: policy) else {
            return []
        }
        let relationshipRecords = PersonaDetectorSupport.records(
            context.relationshipRecords,
            through: trigger.endedAt
        )
        guard relationshipRecords.contains(where: { $0.id == trigger.id }) else { return [] }
        let observations = skippedExercises(
            trigger: trigger,
            records: relationshipRecords,
            context: context,
            policy: policy
        ) + comeback(
            trigger: trigger,
            records: PersonaDetectorSupport.records(context.records, through: trigger.endedAt),
            context: context,
            policy: policy
        )
        return PersonaDetectorSupport.ordered(observations)
    }

    private static func skippedExercises(
        trigger: WorkoutRecord,
        records: [WorkoutRecord],
        context: PersonaContext,
        policy: PersonaPolicy
    ) -> [PersonaObservation] {
        let skippedIDs = Set(trigger.entries.compactMap { entry -> ExerciseID? in
            isSkipped(entry) ? entry.exerciseID : nil
        })
        let sortedRecords = records.sorted { lhs, rhs in
            if lhs.endedAt != rhs.endedAt { return lhs.endedAt > rhs.endedAt }
            return lhs.id.uuidString > rhs.id.uuidString
        }

        var observations: [PersonaObservation] = []
        for exerciseID in skippedIDs.sorted(by: { $0.rawValue < $1.rawValue }) {
            var consecutiveSkips = 0
            for record in sortedRecords {
                let appearances = record.entries.filter { $0.exerciseID == exerciseID }
                guard !appearances.isEmpty else { continue }
                guard appearances.allSatisfy(isSkipped) else { break }
                consecutiveSkips += 1
            }
            guard consecutiveSkips >= policy.skippedExerciseThreshold,
                  let triggerEntry = trigger.entries.first(where: { $0.exerciseID == exerciseID }) else {
                continue
            }
            let escalated = consecutiveSkips >= policy.skippedExerciseEscalated
            let contentKey = escalated
                ? "lapse.skippedExercise.escalated"
                : "lapse.skippedExercise"
            let reachedThreshold = escalated
                ? policy.skippedExerciseEscalated
                : policy.skippedExerciseThreshold
            let strength = max(policy.negativeMinimumStrength, min(5, consecutiveSkips))
            observations.append(PersonaObservation(
                key: PersonaObservationKey(
                    family: .lapse,
                    kind: "skippedExercise",
                    subject: exerciseID.rawValue,
                    period: String(reachedThreshold)
                ),
                salience: .medium,
                evidence: PersonaEvidence(
                    strength: strength,
                    lines: ["\(consecutiveSkips) consecutive skips"]
                ),
                contentKey: contentKey,
                values: [
                    "exercise": PersonaDetectorSupport.exerciseName(exerciseID, entry: triggerEntry, context: context),
                    "count": String(consecutiveSkips)
                ],
                relatedWorkoutID: trigger.id,
                relatedExerciseID: exerciseID
            ))
        }
        return observations
    }

    private static func isSkipped(_ entry: WorkoutRecordEntry) -> Bool {
        entry.outcome == .skipped || entry.sets.isEmpty
    }

    private static func comeback(
        trigger: WorkoutRecord,
        records: [WorkoutRecord],
        context: PersonaContext,
        policy: PersonaPolicy
    ) -> [PersonaObservation] {
        let calendar = context.calendar
        let triggerDay = calendar.startOfDay(for: trigger.endedAt)
        guard !records.contains(where: { record in
            record.id != trigger.id && calendar.isDate(record.endedAt, inSameDayAs: triggerDay)
        }),
        let previousDay = records
            .filter({ calendar.startOfDay(for: $0.endedAt) < triggerDay })
            .map({ calendar.startOfDay(for: $0.endedAt) })
            .max(),
        let gap = calendar.dateComponents([.day], from: previousDay, to: triggerDay).day,
        gap >= policy.comebackDays else {
            return []
        }

        let earlierWorkoutCount = records.filter { $0.endedAt < trigger.endedAt }.count
        let high = gap >= policy.highComebackDays && earlierWorkoutCount >= policy.highComebackPriorWorkouts
        return [PersonaObservation(
            key: PersonaObservationKey(
                family: .lapse,
                kind: "comeback",
                subject: "-",
                period: PersonaDetectorSupport.dayKey(trigger.endedAt, calendar: calendar)
            ),
            salience: high ? .high : .medium,
            evidence: PersonaEvidence(
                strength: high ? 5 : 4,
                lines: ["\(gap) days since the previous workout"]
            ),
            contentKey: "lapse.comeback",
            values: ["days": String(gap)],
            relatedWorkoutID: trigger.id
        )]
    }

    private static func neglectedRoutine(
        context: PersonaContext,
        asOf: Date,
        policy: PersonaPolicy
    ) -> [PersonaObservation] {
        let records = PersonaDetectorSupport.records(context.relationshipRecords, through: asOf)
        let candidates = context.routineNames.keys.compactMap { routineID -> NeglectedRoutine? in
            let runs = records.filter { $0.planID == routineID }
            guard runs.count >= policy.neglectedRoutineMinimumRuns,
                  let lastRun = runs.max(by: { $0.endedAt < $1.endedAt }) else {
                return nil
            }
            let daysSince = context.calendar.dateComponents([.day], from: lastRun.endedAt, to: asOf).day ?? 0
            let weeksSince = daysSince / 7
            guard weeksSince >= policy.neglectedRoutineWeeks else { return nil }
            let otherRuns = records.filter {
                $0.endedAt > lastRun.endedAt && $0.planID != routineID
            }.count
            guard otherRuns >= policy.neglectedRoutineOtherWorkouts else { return nil }
            return NeglectedRoutine(
                id: routineID,
                name: context.routineNames[routineID] ?? "",
                runCount: runs.count,
                lastRun: lastRun,
                weeksSince: weeksSince
            )
        }
        guard let selected = candidates.sorted(by: neglectedRoutinePrecedes).first else { return [] }
        let strength = min(
            5,
            policy.negativeMinimumStrength + selected.weeksSince - policy.neglectedRoutineWeeks
        )
        return [PersonaObservation(
            key: PersonaObservationKey(
                family: .lapse,
                kind: "neglectedRoutine",
                subject: selected.id.uuidString,
                period: PersonaDetectorSupport.weekKey(asOf, calendar: context.calendar)
            ),
            salience: .medium,
            evidence: PersonaEvidence(
                strength: strength,
                lines: ["\(selected.runCount) earlier sessions", "Last used \(selected.weeksSince) weeks ago"]
            ),
            contentKey: "lapse.neglectedRoutine",
            values: ["routine": selected.name, "weeks": String(selected.weeksSince)],
            relatedWorkoutID: selected.lastRun.id,
            suggestion: .routine(id: selected.id, name: selected.name)
        )]
    }

    private struct NeglectedRoutine {
        let id: UUID
        let name: String
        let runCount: Int
        let lastRun: WorkoutRecord
        let weeksSince: Int
    }

    private static func neglectedRoutinePrecedes(_ lhs: NeglectedRoutine, _ rhs: NeglectedRoutine) -> Bool {
        if lhs.runCount != rhs.runCount { return lhs.runCount > rhs.runCount }
        if lhs.lastRun.endedAt != rhs.lastRun.endedAt { return lhs.lastRun.endedAt < rhs.lastRun.endedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func decliningWeeks(
        context: PersonaContext,
        asOf: Date,
        policy: PersonaPolicy
    ) -> [PersonaObservation] {
        let calendar = context.calendar
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: asOf),
              let priorWeekProbe = calendar.date(byAdding: .second, value: -1, to: currentWeek.start),
              let newestPriorWeek = calendar.dateInterval(of: .weekOfYear, for: priorWeekProbe),
              let middleWeekProbe = calendar.date(byAdding: .second, value: -1, to: newestPriorWeek.start),
              let middlePriorWeek = calendar.dateInterval(of: .weekOfYear, for: middleWeekProbe),
              let oldestWeekProbe = calendar.date(byAdding: .second, value: -1, to: middlePriorWeek.start),
              let oldestPriorWeek = calendar.dateInterval(of: .weekOfYear, for: oldestWeekProbe) else {
            return []
        }
        let records = PersonaDetectorSupport.records(context.relationshipRecords, through: asOf)
        let oldestCount = count(records, in: oldestPriorWeek)
        let middleCount = count(records, in: middlePriorWeek)
        let newestCount = count(records, in: newestPriorWeek)
        guard oldestCount >= policy.decliningWeeksMinimumStart,
              oldestCount > middleCount,
              middleCount > newestCount else {
            return []
        }

        var values: [String: String] = [:]
        var suggestion: PersonaSuggestion?
        if let routine = shortestRoutine(context: context) {
            values["suggestion"] = "\(routine.name) · about \(routine.minutes) min"
            suggestion = .routine(id: routine.id, name: routine.name)
        }
        return [PersonaObservation(
            key: PersonaObservationKey(
                family: .lapse,
                kind: "decliningWeeks",
                subject: "-",
                period: PersonaDetectorSupport.weekKey(asOf, calendar: calendar)
            ),
            salience: .medium,
            evidence: PersonaEvidence(
                strength: policy.negativeMinimumStrength,
                lines: ["\(oldestCount), then \(middleCount), then \(newestCount) workouts"]
            ),
            contentKey: "lapse.decliningWeeks",
            values: values,
            suggestion: suggestion
        )]
    }

    private static func count(_ records: [WorkoutRecord], in interval: DateInterval) -> Int {
        records.filter { $0.endedAt >= interval.start && $0.endedAt < interval.end }.count
    }

    private struct RoutineSuggestion {
        let id: UUID
        let name: String
        let minutes: Int
    }

    private static func shortestRoutine(context: PersonaContext) -> RoutineSuggestion? {
        context.routineNames.compactMap { id, name in
            guard let minutes = context.routineMinutes[id] else { return nil }
            return RoutineSuggestion(id: id, name: name, minutes: minutes)
        }.sorted {
            if $0.minutes != $1.minutes { return $0.minutes < $1.minutes }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id.uuidString < $1.id.uuidString
        }.first
    }
}
