import Foundation

/// Streak and recent-history facts derived from saved workout records.
struct PlannedDaysStreak: Equatable {
    let current: Int
    let longest: Int
    let previousRecord: Int
    let totalWorkoutDays: Int
    let lastWorkoutDay: Date?
    let daysSinceLastWorkout: Int?
    let consecutiveMissedPlannedDays: Int
    let brokenRunLength: Int
    let priorRunLength: Int
    let todayIsPlanned: Bool
    let todayCompleted: Bool

    /// Summarizes planned-day runs through the calendar day containing `asOf`.
    static func summarize(
        records: [WorkoutRecord], settings: WorkoutReminderSettings, asOf: Date, calendar: Calendar
    ) -> PlannedDaysStreak {
        let today = calendar.startOfDay(for: asOf)
        let workoutDays = Set(records.filter { $0.endedAt <= asOf }.map { calendar.startOfDay(for: $0.endedAt) })
        let firstDay = workoutDays.min() ?? today
        let plannedDays = PlannedDays.list(in: firstDay...today, settings: settings, calendar: calendar)
        let plannedSet = Set(plannedDays)
        let todayIsPlanned = PlannedDays.isPlanned(today, settings: settings, calendar: calendar)
        let todayCompleted = workoutDays.contains(today)
        let runs = runLengths(plannedDays: plannedDays, workoutDays: workoutDays)
        let missedCount = missedDaysBeforeToday(
            today: today, firstDay: firstDay, plannedDays: plannedSet,
            workoutDays: workoutDays, calendar: calendar
        )
        let brokenRun = runBeforeMissedStretch(
            today: today, firstDay: firstDay, plannedDays: plannedSet,
            workoutDays: workoutDays, calendar: calendar
        )
        let current = currentRun(
            today: today, firstDay: firstDay, todayIsPlanned: todayIsPlanned,
            todayCompleted: todayCompleted, plannedDays: plannedSet,
            workoutDays: workoutDays, calendar: calendar
        )
        let currentIsOpenRun = current > 0 && (todayCompleted || missedCount == 0)
        let previousRecord = currentIsOpenRun ? (runs.dropLast().max() ?? 0) : (runs.max() ?? 0)
        let priorRun = priorRunLength(
            current: current, brokenRun: brokenRun, today: today, firstDay: firstDay,
            todayIsPlanned: todayIsPlanned, todayCompleted: todayCompleted,
            plannedDays: plannedSet, workoutDays: workoutDays, calendar: calendar
        )
        let lastWorkout = workoutDays.max()
        let daysSince = lastWorkout.map {
            max(0, calendar.dateComponents([.day], from: $0, to: today).day ?? 0)
        }
        return PlannedDaysStreak(
            current: current, longest: runs.max() ?? 0, previousRecord: previousRecord,
            totalWorkoutDays: workoutDays.count, lastWorkoutDay: lastWorkout,
            daysSinceLastWorkout: daysSince, consecutiveMissedPlannedDays: missedCount,
            brokenRunLength: brokenRun, priorRunLength: priorRun,
            todayIsPlanned: todayIsPlanned, todayCompleted: todayCompleted
        )
    }

    /// Counts runs by walking planned days in calendar order.
    private static func runLengths(plannedDays: [Date], workoutDays: Set<Date>) -> [Int] {
        var lengths: [Int] = []
        var length = 0
        for day in plannedDays {
            if workoutDays.contains(day) {
                length += 1
            } else if length > 0 {
                lengths.append(length)
                length = 0
            }
        }
        if length > 0 { lengths.append(length) }
        return lengths
    }

    /// Counts missed planned days strictly before today, ignoring non-planned calendar days.
    private static func missedDaysBeforeToday(
        today: Date, firstDay: Date, plannedDays: Set<Date>, workoutDays: Set<Date>, calendar: Calendar
    ) -> Int {
        let start = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        return walkBackward(from: start, firstDay: firstDay, calendar: calendar) { day in
            guard plannedDays.contains(day) else { return .continue }
            return workoutDays.contains(day) ? .stop : .count
        }
    }

    /// Finds the completed run immediately before the current missed stretch.
    private static func runBeforeMissedStretch(
        today: Date, firstDay: Date, plannedDays: Set<Date>, workoutDays: Set<Date>, calendar: Calendar
    ) -> Int {
        var missedStretch = false
        var count = 0
        let start = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        _ = walkBackward(from: start, firstDay: firstDay, calendar: calendar) { day in
            guard plannedDays.contains(day) else { return .continue }
            if workoutDays.contains(day) {
                if missedStretch { count += 1; return .continue }
                return .stop
            }
            if count > 0 { return .stop }
            missedStretch = true
            return .continue
        }
        return count
    }

    /// Counts the active run, treating an unfinished planned today as pending.
    private static func currentRun(
        today: Date, firstDay: Date, todayIsPlanned: Bool, todayCompleted: Bool,
        plannedDays: Set<Date>, workoutDays: Set<Date>, calendar: Calendar
    ) -> Int {
        let start = todayIsPlanned && !todayCompleted
            ? calendar.date(byAdding: .day, value: -1, to: today) ?? today
            : today
        var count = 0
        _ = walkBackward(from: start, firstDay: firstDay, calendar: calendar) { day in
            guard plannedDays.contains(day) else { return .continue }
            if workoutDays.contains(day) { count += 1; return .continue }
            return .stop
        }
        return count
    }

    /// Returns the run before the missed stretch immediately preceding the active run.
    private static func priorRunLength(
        current: Int, brokenRun: Int, today: Date, firstDay: Date,
        todayIsPlanned: Bool, todayCompleted: Bool, plannedDays: Set<Date>,
        workoutDays: Set<Date>, calendar: Calendar
    ) -> Int {
        guard current > 0 else { return brokenRun }
        var day = todayIsPlanned && !todayCompleted
            ? calendar.date(byAdding: .day, value: -1, to: today) ?? today
            : today
        var activeDays = 0
        var foundMissedStretch = false
        var priorRun = 0
        while day >= firstDay {
            if plannedDays.contains(day) {
                if !foundMissedStretch {
                    if workoutDays.contains(day) {
                        activeDays += 1
                    } else if activeDays > 0 {
                        foundMissedStretch = true
                    } else {
                        break
                    }
                } else if workoutDays.contains(day) {
                    priorRun += 1
                } else if priorRun > 0 {
                    break
                }
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return priorRun
    }

    /// Tells a backward scan whether to continue, count a day, or stop.
    private enum WalkDecision { case `continue`, count, stop }

    /// Visits calendar days backwards, stopping at the earliest relevant day or caller decision.
    private static func walkBackward(
        from start: Date, firstDay: Date, calendar: Calendar, visit: (Date) -> WalkDecision
    ) -> Int {
        var total = 0
        var day = start
        while day >= firstDay {
            switch visit(day) {
            case .continue: break
            case .count: total += 1
            case .stop: return total
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return total
    }
}
