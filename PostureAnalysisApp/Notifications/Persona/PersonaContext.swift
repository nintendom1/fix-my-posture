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

    /// No persona notification has fired yet since the last reset, so the next one introduces the feature.
    var isIntro: Bool { traceState.fired(asOf: now).isEmpty }
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
        // Implemented by P1.
        PersonaContext(
            now: now,
            calendar: calendar,
            trigger: trigger,
            appIsActive: appIsActive,
            settings: settings,
            extraPersonableEnabled: extraPersonableEnabled,
            personaResetDate: personaResetDate,
            familiarity: .new,
            trajectory: .unknown,
            streak: PlannedDaysStreak.summarize(records: history.records, settings: settings, asOf: now, calendar: calendar),
            records: history.records,
            relationshipRecords: history.records,
            assessments: history.assessments,
            routineNames: history.routineNames,
            routineMinutes: history.routineMinutes,
            exerciseNames: history.exerciseNames,
            reminderSlotTimes: [],
            traceState: traceState,
            acknowledgmentWillFire: acknowledgmentWillFire
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
        // Implemented by P1.
        .new
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
        // Implemented by P1.
        .unknown
    }
}
