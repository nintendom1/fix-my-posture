import Foundation

/// A reminder position, also used as the stable slot index in identifiers and copy selection.
enum NotificationSlot: Int, CaseIterable { case reminder = 0, followUp = 1, finalWarning = 2 }

/// A chosen scenario and the numeric placeholders needed to render it.
struct NotificationSelection: Equatable {
    let scenarioID: String
    var values: NotificationValues
}

/// Context needed to select a nudge scenario.
struct NudgeFacts {
    let slot: NotificationSlot
    let summary: PlannedDaysStreak
    let isFirstEverNotification: Bool
    let lateNight: Bool
    let hasRecentHistory: Bool
    let habitualIgnorer: Bool
    let dayNumber: Int
    let recentConsistency: Int
    let isWeekend: Bool
    let reminderHour: Int
}

/// Derived context for selecting an acknowledgment after a workout is saved.
struct AcknowledgmentFacts {
    let summary: PlannedDaysStreak
    let gapBeforeToday: Int?
    let slotsFiredBefore: Int
    let endedAtHour: Int
    let planned: Bool
    let streakBeforeToday: Int
    let perfectWeek: Bool
    let weeklyRecovery: Bool
    let endedBeforeFirstSlot: Bool
    let priorNotificationFreeCompletions: Int
}

/// Selects the first matching scenario and derives its template values.
enum NotificationScenarioSelector {
    /// Builds nudge facts from saved records and the configured schedule.
    static func nudgeFacts(
        day: Date, slot: NotificationSlot, slotTime: Date, records: [WorkoutRecord],
        settings: WorkoutReminderSettings, isFirstEverNotification: Bool,
        calendar: Calendar, policy: NotificationPolicy = .standard
    ) -> NudgeFacts {
        let day = calendar.startOfDay(for: day)
        let summary = PlannedDaysStreak.summarize(
            records: records, settings: settings, asOf: day, calendar: calendar
        )
        let lastWorkout = summary.lastWorkoutDay
        let daysSince = lastWorkout.map { calendar.dateComponents([.day], from: $0, to: day).day ?? Int.max }
        let hasRecentHistory = daysSince.map { $0 <= policy.recentHistoryDays } ?? false
        let previousDay = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        let priorRecords = records.filter { calendar.startOfDay(for: $0.endedAt) < day }
        let historyStart = calendar.date(byAdding: .weekOfYear, value: -policy.consistencyWindow, to: day) ?? day
        let plannedBefore = historyStart <= previousDay
            ? PlannedDays.list(in: historyStart...previousDay, settings: settings, calendar: calendar)
            : []
        let completedDays = plannedBefore.filter { plannedDay in
            priorRecords.contains { calendar.isDate($0.endedAt, inSameDayAs: plannedDay) }
        }
        let recentConsistency = plannedBefore.suffix(policy.consistencyWindow).filter { plannedDay in
            priorRecords.contains { calendar.isDate($0.endedAt, inSameDayAs: plannedDay) }
        }.count
        let slotTimes = NotificationSlotSchedule.slots(
            day: day, settings: settings, calendar: calendar, policy: policy
        )
        let followUpTime = slotTimes.first { $0.slot == .followUp }?.time
        let habitualIgnorer = isHabitualIgnorer(
            completedDays: completedDays, records: priorRecords, followUpTime: followUpTime,
            calendar: calendar, policy: policy
        )
        let weekday = calendar.component(.weekday, from: day)
        return NudgeFacts(
            slot: slot, summary: summary, isFirstEverNotification: isFirstEverNotification,
            lateNight: calendar.component(.hour, from: slotTime) >= policy.lateNightHour,
            hasRecentHistory: hasRecentHistory, habitualIgnorer: habitualIgnorer,
            dayNumber: NotificationCopyPicker.dayNumber(for: day, calendar: calendar),
            recentConsistency: recentConsistency, isWeekend: weekday == 1 || weekday == 7,
            reminderHour: settings.hour
        )
    }

    /// Selects a nudge, following the brief's rule order.
    static func select(
        nudge facts: NudgeFacts, policy: NotificationPolicy = .standard
    ) -> NotificationSelection {
        let summary = facts.summary
        switch facts.slot {
        case .reminder:
            if facts.isFirstEverNotification { return selection("first-ever-notification") }
            if summary.consecutiveMissedPlannedDays == 1 && summary.brokenRunLength >= policy.meaningfulStreak {
                return selection("streak-broken", .streak, summary.brokenRunLength)
            }
            if summary.consecutiveMissedPlannedDays == 2 && summary.brokenRunLength >= policy.meaningfulStreak {
                return selection("immediate-post-break")
            }
            if let days = summary.daysSinceLastWorkout, days >= policy.longAbsenceDays {
                return selection("long-absence", .days, days)
            }
            if summary.totalWorkoutDays == 0 { return selection("never-established-history") }
            if facts.lateNight && facts.hasRecentHistory {
                let id = summary.current >= policy.meaningfulStreak
                    ? "late-night-streak-at-risk" : "late-night-reminder"
                return selection(id, .streak, summary.current >= policy.meaningfulStreak ? summary.current : nil)
            }
            let remaining = summary.previousRecord + 1 - summary.current
            if summary.current >= policy.meaningfulStreak,
               summary.previousRecord >= policy.personalBestMinimumRecord,
               (1...policy.approachingRecordWindow).contains(remaining) {
                return NotificationSelection(scenarioID: "approaching-personal-best", values: [
                    .streak: String(summary.current), .record: String(summary.previousRecord),
                    .remaining: String(remaining)
                ])
            }
            if summary.current == policy.almostWeekStreak {
                return selection("almost-one-week", .streak, summary.current)
            }
            if summary.current >= policy.meaningfulStreak {
                return selection("established-streak-reminder", .streak, summary.current)
            }
            if policy.earlyStreakRange.contains(summary.current) {
                return selection("early-streak-forming", .streak, summary.current)
            }
            if summary.current <= 1 && facts.recentConsistency >= policy.consistencyThreshold {
                return selection("neutral-check-in")
            }
            if facts.reminderHour < policy.morningCutoffHour { return selection("morning-reminder") }
            if facts.isWeekend { return selection("weekend-reminder") }
            return selection("ordinary-daily-reminder")
        case .followUp:
            if facts.lateNight {
                let id = summary.current >= policy.meaningfulStreak
                    ? "late-night-streak-at-risk" : "late-night-reminder"
                return selection(id, .streak, summary.current >= policy.meaningfulStreak ? summary.current : nil)
            }
            let highValue = summary.current >= policy.highValueStreak
                || (summary.current >= policy.highValuePersonalBestMinimum
                    && summary.current >= summary.previousRecord)
            if highValue { return selection("high-value-streak-at-risk", .streak, summary.current) }
            if summary.current >= policy.meaningfulStreak {
                return selection("established-streak-at-risk", .streak, summary.current)
            }
            return selection("first-ignored-reminder")
        case .finalWarning:
            if summary.current >= policy.rareEscalationMinimumStreak,
               facts.dayNumber % policy.rareEscalationOneInN == 0 {
                return selection("rare-escalation", .streak, summary.current)
            }
            if summary.current >= policy.meaningfulStreak && facts.habitualIgnorer {
                return selection("strong-repeated-dismissal", .streak, summary.current)
            }
            if summary.current >= policy.meaningfulStreak {
                return selection("final-streak-warning", .streak, summary.current)
            }
            return selection("repeated-ignored-reminder")
        }
    }

    /// Returns an acknowledgment only for the first saved workout of an enabled day's schedule.
    static func acknowledgment(
        for record: WorkoutRecord, records: [WorkoutRecord], settings: WorkoutReminderSettings,
        calendar: Calendar, policy: NotificationPolicy = .standard
    ) -> NotificationSelection? {
        guard settings.enabled else { return nil }
        let allRecords = records.contains(where: { $0.id == record.id }) ? records : records + [record]
        guard isFirstWorkoutOfDay(records: allRecords, record: record, calendar: calendar) else { return nil }
        let today = calendar.startOfDay(for: record.endedAt)
        let previousRecords = allRecords.filter { $0.id != record.id && $0.endedAt < record.endedAt }
        let summary = PlannedDaysStreak.summarize(
            records: allRecords, settings: settings, asOf: record.endedAt, calendar: calendar
        )
        let previousWorkoutDay = previousRecords.map { calendar.startOfDay(for: $0.endedAt) }.max()
        let gap = previousWorkoutDay.map { calendar.dateComponents([.day], from: $0, to: today).day ?? 0 }
        let planned = PlannedDays.isPlanned(today, settings: settings, calendar: calendar)
        let mondayCalendar = mondayFirst(calendar)
        let week = mondayCalendar.dateInterval(of: .weekOfYear, for: today)
        let weekDays = week.map {
            PlannedDays.list(in: $0.start...mondayCalendar.date(byAdding: .day, value: -1, to: $0.end)!,
                             settings: settings, calendar: calendar)
        } ?? []
        let lastPlannedDay = weekDays.last
        let isLastPlannedDay = lastPlannedDay.map { calendar.isDate($0, inSameDayAs: today) } ?? false
        let completedWeekDays = weekDays.filter { hasWorkout(on: $0, records: allRecords, calendar: calendar) }
        let perfectWeek = isLastPlannedDay && weekDays.count >= policy.perfectWeekMinimumPlannedDays
            && completedWeekDays.count == weekDays.count
        let previousPlannedDay = weekDays.last(where: { $0 < today })
        let hasEarlierMiss = weekDays.contains {
            $0 < today && !hasWorkout(on: $0, records: allRecords, calendar: calendar)
        }
        let weeklyRecovery = isLastPlannedDay && weekDays.count >= policy.perfectWeekMinimumPlannedDays
            && hasEarlierMiss && hasWorkout(on: today, records: allRecords, calendar: calendar)
            && previousPlannedDay.map { hasWorkout(on: $0, records: allRecords, calendar: calendar) } == true
        let priorSummary = PlannedDaysStreak.summarize(
            records: previousRecords, settings: settings, asOf: record.endedAt, calendar: calendar
        )
        let slots = NotificationSlotSchedule.slots(
            day: today, settings: settings, calendar: calendar, policy: policy
        )
        let recent = priorSummary.daysSinceLastWorkout.map { $0 <= policy.recentHistoryDays } ?? false
        let availableSlots = recent ? slots : Array(slots.prefix(1))
        let slotsFiredBefore = availableSlots.filter { $0.time < record.endedAt }.count
        let firstSlot = slots.first?.time
        let previousCompletions = priorPlannedCompletions(
            before: today, records: previousRecords, settings: settings, calendar: calendar,
            limit: policy.notificationFreeLookback
        )
        let earlyCompletions = previousCompletions.filter { completion in
            guard let firstTime = NotificationSlotSchedule.slots(
                day: completion.day, settings: settings, calendar: calendar, policy: policy
            ).first?.time else { return false }
            return completion.record.endedAt < firstTime
        }.count
        let facts = AcknowledgmentFacts(
            summary: summary, gapBeforeToday: gap, slotsFiredBefore: slotsFiredBefore,
            endedAtHour: calendar.component(.hour, from: record.endedAt), planned: planned,
            streakBeforeToday: priorSummary.current, perfectWeek: perfectWeek,
            weeklyRecovery: weeklyRecovery,
            endedBeforeFirstSlot: firstSlot.map { record.endedAt < $0 } ?? false,
            priorNotificationFreeCompletions: earlyCompletions
        )
        return select(acknowledgment: facts, policy: policy)
    }

    /// Selects an acknowledgment from already-derived facts.
    static func select(
        acknowledgment facts: AcknowledgmentFacts, policy: NotificationPolicy = .standard
    ) -> NotificationSelection {
        let summary = facts.summary
        if summary.totalWorkoutDays == 1 { return selection("first-completed-session") }
        if summary.previousRecord >= policy.personalBestMinimumRecord && summary.current > summary.previousRecord {
            return NotificationSelection(scenarioID: "new-personal-best-streak", values: [
                .record: String(summary.previousRecord), .streak: String(summary.current)
            ])
        }
        if policy.isMajorMilestone(summary.current) {
            return selection("major-streak-milestone", .streak, summary.current)
        }
        if summary.current == policy.weekMilestone { return selection("one-week-milestone") }
        if let gap = facts.gapBeforeToday, gap >= policy.longAbsenceDays {
            return selection("comeback-after-long-absence")
        }
        if summary.current == 1 && summary.priorRunLength >= policy.meaningfulStreak,
           (facts.gapBeforeToday ?? 0) < policy.longAbsenceDays {
            return selection("restart-after-broken-streak")
        }
        if summary.current == 2 && summary.priorRunLength >= policy.meaningfulStreak {
            return selection("second-day-after-restart")
        }
        if facts.endedAtHour >= policy.lateNightHour && facts.planned
            && facts.streakBeforeToday >= policy.meaningfulStreak {
            return selection("streak-preserved-last-minute", .streak, summary.current)
        }
        if facts.perfectWeek { return selection("perfect-week") }
        if facts.weeklyRecovery { return selection("weekly-recovery") }
        if facts.slotsFiredBefore >= 1 { return selection("session-completed-after-reminders") }
        if facts.endedBeforeFirstSlot && facts.priorNotificationFreeCompletions >= 2 {
            return selection("notification-free-success")
        }
        return selection("session-completed")
    }

    /// Identifies a first workout of a calendar day when records include the new record.
    static func isFirstWorkoutOfDay(
        records: [WorkoutRecord], record: WorkoutRecord, calendar: Calendar
    ) -> Bool {
        !records.contains {
            $0.id != record.id && calendar.isDate($0.endedAt, inSameDayAs: record.endedAt)
        }
    }

    /// Determines whether enough recent planned-day completions came after the follow-up time.
    private static func isHabitualIgnorer(
        completedDays: [Date], records: [WorkoutRecord], followUpTime: Date?,
        calendar: Calendar, policy: NotificationPolicy
    ) -> Bool {
        guard let followUpTime else { return false }
        let followHour = calendar.component(.hour, from: followUpTime)
        let followMinute = calendar.component(.minute, from: followUpTime)
        let lateCount = completedDays.suffix(policy.habitualIgnoreLookback).filter { day in
            records.contains { record in
                guard calendar.isDate(record.endedAt, inSameDayAs: day) else { return false }
                let hour = calendar.component(.hour, from: record.endedAt)
                let minute = calendar.component(.minute, from: record.endedAt)
                return hour > followHour || (hour == followHour && minute > followMinute)
            }
        }.count
        return lateCount >= policy.habitualIgnoreThreshold
    }

    /// Returns the previous three planned-day completions before the acknowledgment day.
    private static func priorPlannedCompletions(
        before day: Date, records: [WorkoutRecord], settings: WorkoutReminderSettings,
        calendar: Calendar, limit: Int
    ) -> [(day: Date, record: WorkoutRecord)] {
        guard let firstDay = records.map({ calendar.startOfDay(for: $0.endedAt) }).min(), firstDay < day,
              let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else { return [] }
        let planned = PlannedDays.list(in: firstDay...previousDay, settings: settings, calendar: calendar)
        return planned.reversed().compactMap { plannedDay in
            guard let record = records.filter({ calendar.isDate($0.endedAt, inSameDayAs: plannedDay) })
                .max(by: { $0.endedAt < $1.endedAt }) else { return nil }
            return (plannedDay, record)
        }.prefix(limit).map { $0 }
    }

    /// Checks whether a calendar day contains a saved workout.
    private static func hasWorkout(on day: Date, records: [WorkoutRecord], calendar: Calendar) -> Bool {
        records.contains { calendar.isDate($0.endedAt, inSameDayAs: day) }
    }

    /// Uses Monday as the first weekday for weekly acknowledgment rules.
    private static func mondayFirst(_ calendar: Calendar) -> Calendar {
        var copy = calendar
        copy.firstWeekday = 2
        return copy
    }

    /// Makes a selection and optionally includes one numeric token.
    private static func selection(
        _ scenarioID: String, _ token: NotificationToken? = nil, _ number: Int? = nil
    ) -> NotificationSelection {
        var values: NotificationValues = [:]
        if let token, let number { values[token] = String(number) }
        return NotificationSelection(scenarioID: scenarioID, values: values)
    }
}
