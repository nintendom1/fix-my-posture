import Foundation

/// Everything one persona evaluation needs, derived from history at evaluation time. Nothing here is a
/// mutable relationship state machine: familiarity and trajectory are recomputed from records every time.
struct PersonaContext: Equatable {
    let now: Date
    let calendar: Calendar
    let trigger: PersonaTrigger
    /// True when the user is interacting with the app, which allows immediate messages even in quiet hours.
    let appIsActive: Bool
    let settings: WorkoutReminderSettings
    let extraPersonableEnabled: Bool
    let personaResetDate: Date?
    let familiarity: PersonaFamiliarity
    let trajectory: PersonaTrajectory
    /// `PlannedDaysStreak.summarize(records:settings:asOf: now ...)`.
    let streak: PlannedDaysStreak
    /// Every workout ever, oldest first, including the triggering record. Used for factual records (PRs, milestones).
    let records: [WorkoutRecord]
    /// Workouts that ended at or after `personaResetDate` (all of them when it is nil), oldest first.
    /// Used for familiarity, patterns, lapses, and callbacks.
    let relationshipRecords: [WorkoutRecord]
    /// Every assessment, oldest first.
    let assessments: [PostureAssessment]
    let routineNames: [UUID: String]
    let routineMinutes: [UUID: Int]
    let exerciseNames: [ExerciseID: String]
    /// Reminder slot times from today through the projection horizon, so projected messages can keep their distance.
    let reminderSlotTimes: [Date]
    let traceState: PersonaTraceState
    /// True when the workout acknowledgment for the triggering record is about to fire, so persona content can ride on it.
    let acknowledgmentWillFire: Bool

    /// Extra Personable, reminders, and Character style are all on.
    var isActive: Bool {
        extraPersonableEnabled && settings.enabled && settings.style == .character
    }

    /// Everything the persona read, unflattened, so a new `PersonaHistory` source (for example HealthKit facts) reaches
    /// detectors through `context.history` without changing this type or the builder.
    var history = PersonaHistory()

    /// Nothing has been sent or folded since the last reset (pending immediate and folded messages count), so the next
    /// message introduces the feature. The planner gives the intro only to the first winner of a plan.
    var isIntro: Bool { traceState.committed(asOf: now).isEmpty }
}

enum PersonaContextBuilder {
    /// Builds the context. Sorts records and assessments oldest first, filters relationship records by the reset
    /// date, computes the streak, familiarity, trajectory, and reminder slot times for today through the horizon.
    static func build(
        history: PersonaHistory,
        settings: WorkoutReminderSettings,
        extraPersonableEnabled: Bool,
        personaResetDate: Date?,
        traceState: PersonaTraceState,
        trigger: PersonaTrigger,
        acknowledgmentWillFire: Bool,
        appIsActive: Bool,
        now: Date,
        calendar: Calendar,
        policy: PersonaPolicy = .standard
    ) -> PersonaContext {
        let records = history.records.sorted {
            if $0.endedAt != $1.endedAt { return $0.endedAt < $1.endedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        let relationshipRecords = records.filter { record in
            guard let personaResetDate else { return true }
            return record.endedAt >= personaResetDate
        }
        let assessments = history.assessments.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id.uuidString < $1.id.uuidString
        }
        let reminderSlotTimes = slotTimes(
            settings: settings,
            now: now,
            calendar: calendar,
            policy: policy
        )

        return PersonaContext(
            now: now,
            calendar: calendar,
            trigger: trigger,
            appIsActive: appIsActive,
            settings: settings,
            extraPersonableEnabled: extraPersonableEnabled,
            personaResetDate: personaResetDate,
            familiarity: familiarity(records: relationshipRecords, resetDate: nil, now: now, calendar: calendar, policy: policy),
            trajectory: trajectory(records: relationshipRecords, now: now, calendar: calendar, policy: policy),
            streak: PlannedDaysStreak.summarize(records: records, settings: settings, asOf: now, calendar: calendar),
            records: records,
            relationshipRecords: relationshipRecords,
            assessments: assessments,
            routineNames: history.routineNames,
            routineMinutes: history.routineMinutes,
            exerciseNames: history.exerciseNames,
            reminderSlotTimes: reminderSlotTimes,
            traceState: traceState,
            acknowledgmentWillFire: acknowledgmentWillFire,
            history: history
        )
    }

    /// Distinct workout days (by `endedAt` in `calendar`) at or after `resetDate`: fewer than 5 is new, 5–14 familiar,
    /// 15–39 established, 40 or more long-term when the first and last counted days are at least 8 weeks apart
    /// (otherwise established).
    static func familiarity(
        records: [WorkoutRecord],
        resetDate: Date?,
        now: Date,
        calendar: Calendar,
        policy: PersonaPolicy = .standard
    ) -> PersonaFamiliarity {
        let workoutDays = Set(records.compactMap { record -> Date? in
            guard record.endedAt <= now else { return nil }
            if let resetDate, record.endedAt < resetDate { return nil }
            return calendar.startOfDay(for: record.endedAt)
        }).sorted()

        let count = workoutDays.count
        if count < policy.familiarWorkoutDays { return .new }
        if count < policy.establishedWorkoutDays { return .familiar }
        if count < policy.longTermWorkoutDays { return .established }
        guard let first = workoutDays.first,
              let last = workoutDays.last,
              let longTermBoundary = calendar.date(
                byAdding: .weekOfYear,
                value: policy.longTermMinimumWeeks,
                to: first
              ),
              last >= longTermBoundary else {
            return .established
        }
        return .longTerm
    }

    /// Workouts ending in the last `trajectoryWindowDays` days versus the window before it. A difference of at least
    /// `trajectoryChangeThreshold` is improving or declining; otherwise stable. Fewer than `trajectoryMinimumWorkouts`
    /// across both windows is unknown.
    static func trajectory(
        records: [WorkoutRecord],
        now: Date,
        calendar: Calendar,
        policy: PersonaPolicy = .standard
    ) -> PersonaTrajectory {
        guard let recentStart = calendar.date(byAdding: .day, value: -policy.trajectoryWindowDays, to: now),
              let previousStart = calendar.date(byAdding: .day, value: -2 * policy.trajectoryWindowDays, to: now) else {
            return .unknown
        }

        let recent = records.filter { $0.endedAt > recentStart && $0.endedAt <= now }.count
        let previous = records.filter { $0.endedAt > previousStart && $0.endedAt <= recentStart }.count
        guard recent + previous >= policy.trajectoryMinimumWorkouts else { return .unknown }
        if recent - previous >= policy.trajectoryChangeThreshold { return .improving }
        if previous - recent >= policy.trajectoryChangeThreshold { return .declining }
        return .stable
    }

    /// Collects scheduled reminder slots from today through the configured projection horizon.
    private static func slotTimes(
        settings: WorkoutReminderSettings,
        now: Date,
        calendar: Calendar,
        policy: PersonaPolicy
    ) -> [Date] {
        guard settings.enabled else { return [] }
        let firstDay = calendar.startOfDay(for: now)
        guard let horizon = calendar.date(byAdding: .day, value: policy.projectionHorizonDays, to: now) else {
            return []
        }
        let lastDay = calendar.startOfDay(for: horizon)
        var times: [Date] = []
        var day = firstDay
        while day <= lastDay {
            if PlannedDays.isPlanned(day, settings: settings, calendar: calendar) {
                times.append(contentsOf: NotificationSlotSchedule.slots(
                    day: day,
                    settings: settings,
                    calendar: calendar
                ).map(\.time))
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }
        return times.sorted()
    }
}
