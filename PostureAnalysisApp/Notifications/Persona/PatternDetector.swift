import Foundation

/// Pattern observations. See the detector table in docs/persona.md and PersonaPolicy for thresholds.
enum PatternDetector: PersonaDetecting {
    static func observations(
        _ context: PersonaContext,
        asOf: Date,
        projected: Bool,
        policy: PersonaPolicy
    ) -> [PersonaObservation] {
        if projected {
            return PersonaDetectorSupport.ordered(upcomingWeekday(context: context, asOf: asOf, policy: policy))
        }
        guard let trigger = PersonaDetectorSupport.freshTriggerRecord(in: context, asOf: asOf, policy: policy) else {
            return []
        }

        let relationshipRecords = PersonaDetectorSupport.records(
            context.relationshipRecords,
            through: trigger.endedAt
        )
        guard relationshipRecords.contains(where: { $0.id == trigger.id }) else { return [] }
        var observations = weekdayPattern(
            trigger: trigger,
            records: relationshipRecords,
            context: context,
            policy: policy
        )
        observations.append(contentsOf: routineRepeat(
            trigger: trigger,
            records: relationshipRecords,
            context: context,
            policy: policy
        ))
        observations.append(contentsOf: timeOfDay(
            trigger: trigger,
            records: relationshipRecords,
            context: context,
            policy: policy
        ))
        return PersonaDetectorSupport.ordered(observations)
    }

    private static func weekdayPattern(
        trigger: WorkoutRecord,
        records: [WorkoutRecord],
        context: PersonaContext,
        policy: PersonaPolicy
    ) -> [PersonaObservation] {
        let calendar = context.calendar
        let triggerDay = calendar.startOfDay(for: trigger.endedAt)
        guard !records.contains(where: { record in
            record.id != trigger.id && calendar.isDate(record.endedAt, inSameDayAs: triggerDay)
        }) else { return [] }

        var consecutiveWeeks = 0
        var day = triggerDay
        while records.contains(where: { calendar.isDate($0.endedAt, inSameDayAs: day) }) {
            consecutiveWeeks += 1
            guard let previousWeek = calendar.date(byAdding: .day, value: -7, to: day) else { break }
            day = previousWeek
        }
        guard consecutiveWeeks >= policy.patternTentative else { return [] }

        let salience: PersonaSalience
        let strength: Int
        if consecutiveWeeks < policy.patternEmerging {
            salience = .low
            strength = 2
        } else if consecutiveWeeks < policy.patternEstablished {
            salience = .medium
            strength = 3
        } else {
            salience = .medium
            strength = 4
        }
        let weekday = calendar.component(.weekday, from: triggerDay)
        let weekdayName = PersonaDetectorSupport.weekdayName(triggerDay, calendar: calendar)
        return [PersonaObservation(
            key: PersonaObservationKey(
                family: .pattern,
                kind: "weekday",
                subject: String(weekday),
                period: PersonaDetectorSupport.weekKey(triggerDay, calendar: calendar)
            ),
            salience: salience,
            evidence: PersonaEvidence(
                strength: strength,
                lines: ["\(consecutiveWeeks) consecutive \(weekdayName)s"]
            ),
            contentKey: consecutiveWeeks >= policy.patternEstablished
                ? "pattern.weekday.established"
                : "pattern.weekday",
            values: ["weekday": weekdayName, "count": String(consecutiveWeeks)],
            relatedWorkoutID: trigger.id
        )]
    }

    private static func upcomingWeekday(
        context: PersonaContext,
        asOf: Date,
        policy: PersonaPolicy
    ) -> [PersonaObservation] {
        let calendar = context.calendar
        let slotDay = calendar.startOfDay(for: asOf)
        let records = PersonaDetectorSupport.records(context.relationshipRecords, through: asOf)
        guard !records.contains(where: { calendar.isDate($0.endedAt, inSameDayAs: slotDay) }) else { return [] }

        var previousWeeks = 0
        guard var day = calendar.date(byAdding: .day, value: -7, to: slotDay) else { return [] }
        while records.contains(where: { calendar.isDate($0.endedAt, inSameDayAs: day) }) {
            previousWeeks += 1
            guard let previousWeek = calendar.date(byAdding: .day, value: -7, to: day) else { break }
            day = previousWeek
        }
        guard previousWeeks >= policy.patternTentative else { return [] }

        let salience: PersonaSalience = previousWeeks == policy.patternTentative ? .low : .medium
        let strength = previousWeeks == policy.patternTentative ? 2 : 3
        let weekday = calendar.component(.weekday, from: slotDay)
        let weekdayName = PersonaDetectorSupport.weekdayName(slotDay, calendar: calendar)
        return [PersonaObservation(
            key: PersonaObservationKey(
                family: .pattern,
                kind: "weekday.upcoming",
                subject: String(weekday),
                period: PersonaDetectorSupport.weekKey(slotDay, calendar: calendar)
            ),
            salience: salience,
            evidence: PersonaEvidence(
                strength: strength,
                lines: ["\(previousWeeks) previous \(weekdayName)s", "\(previousWeeks + 1) would make a pattern"]
            ),
            contentKey: "pattern.weekday.upcoming",
            values: ["weekday": weekdayName, "count": String(previousWeeks + 1)]
        )]
    }

    private static func routineRepeat(
        trigger: WorkoutRecord,
        records: [WorkoutRecord],
        context: PersonaContext,
        policy: PersonaPolicy
    ) -> [PersonaObservation] {
        guard let planID = trigger.planID else { return [] }
        let sortedRecords = records.sorted { lhs, rhs in
            if lhs.endedAt != rhs.endedAt { return lhs.endedAt > rhs.endedAt }
            if lhs.id == rhs.id { return false }
            if lhs.id == trigger.id { return true }
            if rhs.id == trigger.id { return false }
            return lhs.id.uuidString > rhs.id.uuidString
        }
        guard sortedRecords.first?.id == trigger.id else { return [] }

        var count = 0
        for record in sortedRecords {
            guard record.planID == planID,
                  let daysApart = context.calendar.dateComponents(
                    [.day],
                    from: context.calendar.startOfDay(for: record.endedAt),
                    to: context.calendar.startOfDay(for: trigger.endedAt)
                  ).day,
                  daysApart >= 0,
                  daysApart <= policy.routineRepeatWindowDays else {
                break
            }
            count += 1
        }
        guard count == policy.routineRepeatTentative || count == policy.routineRepeatEstablished else {
            return []
        }

        let salience: PersonaSalience = count == policy.routineRepeatTentative ? .low : .medium
        return [PersonaObservation(
            key: PersonaObservationKey(
                family: .pattern,
                kind: "routineRepeat",
                subject: planID.uuidString,
                period: String(count)
            ),
            salience: salience,
            evidence: PersonaEvidence(
                strength: count == policy.routineRepeatTentative ? 2 : 4,
                lines: ["\(count) sessions in a row"]
            ),
            contentKey: "pattern.routineRepeat",
            values: [
                "routine": PersonaDetectorSupport.routineName(planID, record: trigger, context: context),
                "count": String(count)
            ],
            relatedWorkoutID: trigger.id
        )]
    }

    private static func timeOfDay(
        trigger: WorkoutRecord,
        records: [WorkoutRecord],
        context: PersonaContext,
        policy: PersonaPolicy
    ) -> [PersonaObservation] {
        let recentRecords = records.sorted { lhs, rhs in
            if lhs.endedAt != rhs.endedAt { return lhs.endedAt > rhs.endedAt }
            if lhs.id == rhs.id { return false }
            if lhs.id == trigger.id { return true }
            if rhs.id == trigger.id { return false }
            return lhs.id.uuidString > rhs.id.uuidString
        }.prefix(policy.timeOfDayWorkouts)
        guard recentRecords.count == policy.timeOfDayWorkouts else { return [] }

        let hours = recentRecords.map { PersonaDetectorSupport.fractionalHour($0.endedAt, calendar: context.calendar) }
        guard let minimum = hours.min(), let maximum = hours.max(),
              maximum - minimum <= Double(policy.timeOfDayBandHours) else {
            return []
        }
        let meanHour = hours.reduce(0, +) / Double(hours.count)
        guard let time = PersonaDetectorSupport.formattedHour(Int(meanHour.rounded()), on: trigger.endedAt, calendar: context.calendar) else {
            return []
        }
        let minimumHour = Int(minimum.rounded(.down))
        let week = PersonaDetectorSupport.weekKey(trigger.endedAt, calendar: context.calendar)
        return [PersonaObservation(
            key: PersonaObservationKey(
                family: .pattern,
                kind: "timeOfDay",
                subject: String(minimumHour),
                period: week
            ),
            salience: .low,
            evidence: PersonaEvidence(strength: 2, lines: ["\(recentRecords.count) recent sessions around \(time)"]),
            contentKey: "pattern.timeOfDay",
            values: ["time": time],
            relatedWorkoutID: trigger.id
        )]
    }
}
