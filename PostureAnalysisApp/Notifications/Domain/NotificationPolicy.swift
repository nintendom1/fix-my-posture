import Foundation

/// Named thresholds used by notification selection and planning.
struct NotificationPolicy: Equatable {
    static let standard = NotificationPolicy()

    /// Minimum streak considered meaningful.
    let meaningfulStreak: Int
    /// Streaks reinforced as early momentum.
    let earlyStreakRange: ClosedRange<Int>
    /// The six-day near-week streak.
    let almostWeekStreak: Int
    /// The one-week milestone.
    let weekMilestone: Int
    /// Explicit major streak milestones.
    let majorMilestones: [Int]
    /// Interval for major milestones after the listed milestones.
    let majorMilestoneInterval: Int
    /// First streak level considered high value.
    let highValueStreak: Int
    /// Minimum streak for a personal-best-adjacent high-value case.
    let highValuePersonalBestMinimum: Int
    /// Minimum prior run treated as a record.
    let personalBestMinimumRecord: Int
    /// Days from the next record needed to approach it.
    let approachingRecordWindow: Int
    /// Days without a workout that trigger a long absence.
    let longAbsenceDays: Int
    /// Maximum age for recent workout history.
    let recentHistoryDays: Int
    /// Number of prior planned days used for consistency.
    let consistencyWindow: Int
    /// Completed days needed for consistent history.
    let consistencyThreshold: Int
    /// Local hour at which late-night rules begin.
    let lateNightHour: Int
    /// Reminder hour boundary for morning copy.
    let morningCutoffHour: Int
    /// Follow-up delay after the selected reminder time.
    let followUpDelayHours: Int
    /// Latest local hour for a follow-up.
    let followUpLatestHour: Int
    /// Final warning local hour.
    let finalWarningHour: Int
    /// Final warning local minute.
    let finalWarningMinute: Int
    /// Minimum gap between notification slots.
    let minimumSlotGapMinutes: Int
    /// Missed planned days after which reminders taper.
    let taperAfterMissedPlannedDays: Int
    /// Days without a workout after which planning stops.
    let stopAfterDaysWithoutWorkout: Int
    /// Planned days projected ahead.
    let planningHorizonPlannedDays: Int
    /// Maximum requests returned by the planner.
    let maximumRequests: Int
    /// Streak length needed before rare escalation is eligible.
    let rareEscalationMinimumStreak: Int
    /// One rare escalation per this many eligible days.
    let rareEscalationOneInN: Int
    /// Planned completions checked for habitual late workouts.
    let habitualIgnoreLookback: Int
    /// Late completions needed to count as a habitual ignorer.
    let habitualIgnoreThreshold: Int
    /// Previous planned-day completions checked for notification-free acknowledgment.
    let notificationFreeLookback: Int
    /// Minimum planned sessions for perfect-week recognition.
    let perfectWeekMinimumPlannedDays: Int
    /// Delay before an acknowledgment is delivered.
    let acknowledgmentDelaySeconds: Int

    init(
        recentHistoryDays: Int = 14, stopAfterDaysWithoutWorkout: Int = 14,
        taperAfterMissedPlannedDays: Int = 3,
        planningHorizonPlannedDays: Int = 14, maximumRequests: Int = 60
    ) {
        self.meaningfulStreak = 5
        self.earlyStreakRange = 2...4
        self.almostWeekStreak = 6
        self.weekMilestone = 7
        self.majorMilestones = [14, 30, 50, 100]
        self.majorMilestoneInterval = 100
        self.highValueStreak = 21
        self.highValuePersonalBestMinimum = 14
        self.personalBestMinimumRecord = 7
        self.approachingRecordWindow = 3
        self.longAbsenceDays = 7
        self.recentHistoryDays = recentHistoryDays
        self.consistencyWindow = 4
        self.consistencyThreshold = 3
        self.lateNightHour = 21
        self.morningCutoffHour = 10
        self.followUpDelayHours = 3
        self.followUpLatestHour = 21
        self.finalWarningHour = 21
        self.finalWarningMinute = 30
        self.minimumSlotGapMinutes = 30
        self.taperAfterMissedPlannedDays = taperAfterMissedPlannedDays
        self.stopAfterDaysWithoutWorkout = stopAfterDaysWithoutWorkout
        self.planningHorizonPlannedDays = planningHorizonPlannedDays
        self.maximumRequests = maximumRequests
        self.rareEscalationMinimumStreak = 30
        self.rareEscalationOneInN = 5
        self.habitualIgnoreLookback = 7
        self.habitualIgnoreThreshold = 2
        self.notificationFreeLookback = 3
        self.perfectWeekMinimumPlannedDays = 3
        self.acknowledgmentDelaySeconds = 1
    }

    /// Returns whether a streak is an explicit or later hundred-day milestone.
    func isMajorMilestone(_ streak: Int) -> Bool {
        let highestListedMilestone = majorMilestones.max() ?? 0
        return majorMilestones.contains(streak)
            || (streak > highestListedMilestone && streak.isMultiple(of: majorMilestoneInterval))
    }
}
