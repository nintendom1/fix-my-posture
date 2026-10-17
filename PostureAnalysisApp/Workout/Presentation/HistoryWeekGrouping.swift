import Foundation

/// Calendar-week groupings used by workout History.
struct HistoryWeekGrouping: Equatable {
    struct Week: Equatable, Identifiable {
        let startDate: Date
        let title: String
        let summary: String
        let records: [WorkoutRecord]

        var id: Date { startDate }
    }

    let weeks: [Week]

    init(records: [WorkoutRecord], now: Date, calendar: Calendar = .current) {
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2

        guard let thisWeekStart = mondayCalendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let lastWeekStart = mondayCalendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) else {
            weeks = []
            return
        }

        var grouped: [Date: [WorkoutRecord]] = [:]
        for record in records {
            guard let start = mondayCalendar.dateInterval(of: .weekOfYear, for: record.startedAt)?.start else { continue }
            grouped[start, default: []].append(record)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = mondayCalendar
        formatter.timeZone = mondayCalendar.timeZone
        formatter.dateFormat = "MMM d"

        weeks = grouped.keys.sorted(by: >).compactMap { start in
            guard let recordsInWeek = grouped[start] else { return nil }
            let ordered = recordsInWeek.sorted(by: Self.newestFirst)
            let title: String
            if start == thisWeekStart {
                title = "This week"
            } else if start == lastWeekStart {
                title = "Last week"
            } else {
                title = "Week of \(formatter.string(from: start))"
            }
            return Week(
                startDate: start,
                title: title,
                summary: Self.summary(for: ordered),
                records: ordered
            )
        }
    }

    private static func newestFirst(_ lhs: WorkoutRecord, _ rhs: WorkoutRecord) -> Bool {
        if lhs.startedAt != rhs.startedAt { return lhs.startedAt > rhs.startedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func summary(for records: [WorkoutRecord]) -> String {
        let seconds = records.reduce(0.0) { total, record in
            total + max(0, record.endedAt.timeIntervalSince(record.startedAt))
        }
        let minutes = Int((seconds / 60).rounded())
        return "\(records.count) \(records.count == 1 ? "workout" : "workouts") · \(minutes) min"
    }
}
