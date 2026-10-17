import Foundation

/// Current-week totals and a compact, newest-first list for the Progress screen.
struct WeeklyStats: Equatable {
    struct RecentWorkout: Equatable, Identifiable {
        let recordID: UUID
        let name: String
        let meta: String
        let day: String

        var id: UUID { recordID }
    }

    let workouts: [WorkoutRecord]
    let workoutCount: Int
    let setCount: Int
    let repCount: Int
    let durationLabel: String
    let weekRangeLabel: String
    let activeDays: [Bool]
    let todayIndex: Int
    let recent: [RecentWorkout]

    init(records: [WorkoutRecord], now: Date, calendar: Calendar = .current) {
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2

        let weekInterval = mondayCalendar.dateInterval(of: .weekOfYear, for: now)
        let ordered = records.sorted(by: Self.newestFirst)
        let weekRecords = ordered.filter { record in
            guard let weekInterval else { return false }
            return weekInterval.contains(record.startedAt)
        }
        let stats = weekRecords.map(WorkoutCompletionStats.init(record:))

        workouts = weekRecords
        workoutCount = weekRecords.count
        setCount = stats.reduce(0) { $0 + $1.totalSets }
        repCount = stats.reduce(0) { $0 + $1.totalReps }
        durationLabel = Self.compactDuration(seconds: weekRecords.reduce(0) {
            $0 + max(0, $1.endedAt.timeIntervalSince($1.startedAt))
        })

        if let weekInterval,
           let finalDay = mondayCalendar.date(byAdding: .day, value: -1, to: weekInterval.end) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = mondayCalendar
            formatter.timeZone = mondayCalendar.timeZone
            formatter.dateFormat = "MMM d"
            let endDayFormatter = DateFormatter()
            endDayFormatter.locale = formatter.locale
            endDayFormatter.calendar = mondayCalendar
            endDayFormatter.timeZone = mondayCalendar.timeZone
            endDayFormatter.dateFormat = "d"
            weekRangeLabel = "\(formatter.string(from: weekInterval.start)) – \(endDayFormatter.string(from: finalDay))"
            activeDays = (0..<7).map { offset in
                guard let dayStart = mondayCalendar.date(byAdding: .day, value: offset, to: weekInterval.start) else { return false }
                return weekRecords.contains { mondayCalendar.isDate($0.startedAt, inSameDayAs: dayStart) }
            }
            todayIndex = min(6, max(0, mondayCalendar.dateComponents([.day], from: weekInterval.start, to: now).day ?? 0))
        } else {
            weekRangeLabel = ""
            activeDays = Array(repeating: false, count: 7)
            todayIndex = 0
        }

        var dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = mondayCalendar
        dateFormatter.timeZone = mondayCalendar.timeZone
        dateFormatter.dateFormat = "EEE"
        recent = ordered.prefix(3).map { record in
            let completion = WorkoutCompletionStats(record: record)
            let duration = completion.durationLabel == "<1m"
                ? "<1 min"
                : completion.durationLabel.replacingOccurrences(of: "m", with: " min")
            let name = record.planName ?? record.entries.first?.name ?? "Workout"
            return RecentWorkout(
                recordID: record.id,
                name: name,
                meta: "\(duration) · \(completion.totalSets) \(completion.totalSets == 1 ? "set" : "sets") · \(completion.totalReps) \(completion.totalReps == 1 ? "rep" : "reps")",
                day: dateFormatter.string(from: record.startedAt)
            )
        }
    }

    private static func newestFirst(_ lhs: WorkoutRecord, _ rhs: WorkoutRecord) -> Bool {
        if lhs.startedAt != rhs.startedAt { return lhs.startedAt > rhs.startedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func compactDuration(seconds: TimeInterval) -> String {
        "\(Int((seconds / 60).rounded()))m"
    }
}
