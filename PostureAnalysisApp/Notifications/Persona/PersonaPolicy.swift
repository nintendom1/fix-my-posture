import Foundation

/// Every Extra Personable threshold in one place. Detectors, the planner, tone selection, and cooling read
/// these instead of literals so tuning never means hunting through logic.
struct PersonaPolicy: Equatable {
    static let standard = PersonaPolicy()

    // MARK: Familiarity and trajectory

    /// Distinct workout days since the persona reset needed for each familiarity level.
    var familiarWorkoutDays = 5
    var establishedWorkoutDays = 15
    var longTermWorkoutDays = 40
    /// Long-term also needs this many weeks between the first and last counted workout day.
    var longTermMinimumWeeks = 8
    /// Trajectory compares workouts in the last window with the window before it.
    var trajectoryWindowDays = 14
    /// A difference of at least this many workouts is improving or declining.
    var trajectoryChangeThreshold = 2
    /// Fewer workouts than this across both windows is unknown.
    var trajectoryMinimumWorkouts = 4

    // MARK: Delivery

    /// Standalone persona notifications per calendar day, active and passive together. Absolute.
    var dailyStandaloneCap = 2
    /// Calendar days projected ahead (today plus this many days).
    var projectionHorizonDays = 7
    /// Projected notifications per day: 0 turns projection off; v1 plans at most one per day for any positive value.
    var projectedPerDay = 1
    /// Local time for a projected day's notification.
    var projectedHour = 11
    var projectedMinute = 30
    /// Projected notifications stay at least this far from any reminder slot that day.
    var minimumMinutesFromReminderSlot = 90
    /// When today's projected time has passed, today's slot moves to now plus this many minutes.
    var todayFallbackDelayMinutes = 60
    /// Seconds before an immediate standalone notification after a workout save.
    var immediateDelaySeconds = 1
    /// Quiet hours, local time. A provider may replace them later; detectors never read these.
    var quietStartHour = 22
    var quietEndHour = 8
    /// A PR or comeback older than this is no longer fresh enough to announce.
    var achievementFreshnessHours = 36

    // MARK: Repetition and cooling

    /// Fired messages of the same family and kind within this many days lower the salience one step.
    var similarWindowDays = 7
    var similarDowngradeCount = 2
    /// Recent tones considered when choosing the next tone.
    var recentToneLimit = 5
    /// A tone may appear at most this many times among the recent tones before it is avoided.
    var maximumRepeatsOfTone = 1
    /// Fired messages considered for cooling.
    var coolingLookback = 5
    /// Mild cooling: at least this many dismissals and no taps among the lookback.
    var mildCoolingDismissals = 2
    /// Strong cooling: at least this many dismissals among the lookback,
    var strongCoolingDismissals = 3
    /// or this many fired messages in a row with no tap or dismissal within `noResponseHours`.
    var strongCoolingUnanswered = 5
    var noResponseHours = 24
    /// Cooling ignores engagement older than this.
    var coolingDecayDays = 14

    // MARK: Evidence

    /// Pattern confidence ladder: tentative, emerging, established.
    var patternTentative = 3
    var patternEmerging = 4
    var patternEstablished = 5
    /// Negative (lapse) observations need at least this evidence strength and never exceed medium.
    var negativeMinimumStrength = 3
    /// Workout-count milestones; after the last listed one, every `milestoneInterval`.
    var workoutMilestones = [10, 25, 50, 100]
    var milestoneInterval = 50
    /// Milestones at or above this count are high salience.
    var highSalienceMilestone = 50
    /// Comeback after at least this many days without a workout; high with a longer gap and enough history.
    var comebackDays = 14
    var highComebackDays = 28
    var highComebackPriorWorkouts = 10
    /// A weight PR needs this many earlier sessions of the exercise with a mass weight.
    var prMinimumPriorSessions = 3
    /// A weight PR at least this fraction above the previous best is high salience.
    var highWeightPRFraction = 0.10
    /// A rep PR this many reps above the previous best at that weight is high salience.
    var highRepPRIncrease = 3
    /// Same routine this many times in a row within `routineRepeatWindowDays`.
    var routineRepeatTentative = 3
    var routineRepeatEstablished = 5
    var routineRepeatWindowDays = 21
    /// Time-of-day habit: this many most recent workouts ending within a band of this many hours.
    var timeOfDayWorkouts = 5
    var timeOfDayBandHours = 2
    /// Consecutive skipped appearances of an exercise that make a lapse; the escalated copy starts at the second number.
    var skippedExerciseThreshold = 3
    var skippedExerciseEscalated = 6
    /// Neglected routine: done at least this many times, not for this many weeks, with this many other workouts since.
    var neglectedRoutineMinimumRuns = 3
    var neglectedRoutineWeeks = 3
    var neglectedRoutineOtherWorkouts = 3
    /// Declining weeks: three closed weeks strictly decreasing, the first with at least this many workouts.
    var decliningWeeksMinimumStart = 3
    /// Posture: returning after this many days; medium salience after the longer gap.
    var postureReturnDays = 21
    var postureReturnMediumDays = 45
    /// Posture: the newest assessment must be this recent to count as a return.
    var postureReturnFreshnessHours = 36
    /// Posture improvement: degrees closer to zero than the baseline, on two consecutive assessments,
    /// the newest no older than this many days.
    var postureImprovementDegrees = 2.0
    var postureImprovedFreshnessDays = 7

    // MARK: Trace storage

    var sentTraceLimit = 10
    var suppressedTraceLimit = 20
    var engagementLimit = 30

    /// Whether a workout count is a milestone.
    func isWorkoutMilestone(_ count: Int) -> Bool {
        if workoutMilestones.contains(count) { return true }
        let last = workoutMilestones.max() ?? 0
        return count > last && milestoneInterval > 0 && (count - last).isMultiple(of: milestoneInterval)
    }
}
