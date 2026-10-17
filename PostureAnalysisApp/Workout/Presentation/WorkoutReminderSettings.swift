import Foundation

enum WorkoutReminderRecurrence: String, Codable, CaseIterable, Identifiable {
    case daily
    case everyOtherDay
    case weekly

    var id: Self { self }

    var title: String {
        switch self {
        case .daily: "Daily"
        case .everyOtherDay: "Every Other Day"
        case .weekly: "Weekly"
        }
    }
}

/// The one user-configurable workout reminder schedule.
struct WorkoutReminderSettings: Codable, Equatable {
    var enabled: Bool
    var recurrence: WorkoutReminderRecurrence
    var hour: Int
    var minute: Int
    var everyOtherDayStartDate: Date
    /// Calendar weekday values: Sunday is 1 and Saturday is 7.
    var weekdays: Set<Int>

    init(
        enabled: Bool = false,
        recurrence: WorkoutReminderRecurrence = .daily,
        hour: Int = 18,
        minute: Int = 0,
        everyOtherDayStartDate: Date = Calendar.current.startOfDay(for: Date()),
        weekdays: Set<Int> = [2, 4, 6]
    ) {
        self.enabled = enabled
        self.recurrence = recurrence
        self.hour = hour
        self.minute = minute
        self.everyOtherDayStartDate = everyOtherDayStartDate
        self.weekdays = weekdays
    }

    func normalized(calendar: Calendar = .current) -> Self {
        var copy = self
        copy.hour = min(max(hour, 0), 23)
        copy.minute = min(max(minute, 0), 59)
        copy.everyOtherDayStartDate = calendar.startOfDay(for: everyOtherDayStartDate)
        copy.weekdays = Set(weekdays.filter { (1...7).contains($0) })
        if copy.weekdays.isEmpty {
            copy.weekdays = [calendar.firstWeekday]
        }
        return copy
    }

    var summary: String {
        let timeFormatter = DateFormatter()
        timeFormatter.locale = .current
        timeFormatter.timeStyle = .short
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = min(max(hour, 0), 23)
        components.minute = min(max(minute, 0), 59)
        let time = Calendar.current.date(from: components).map(timeFormatter.string(from:))
            ?? "\(hour):\(String(format: "%02d", minute))"

        switch recurrence {
        case .daily:
            return "Daily · \(time)"
        case .everyOtherDay:
            return "Every other day · \(time)"
        case .weekly:
            let symbols = DateFormatter().shortWeekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let selected = (1...7).filter(weekdays.contains).compactMap { weekday -> String? in
                guard symbols.indices.contains(weekday - 1) else { return nil }
                return symbols[weekday - 1]
            }
            return "\(selected.joined(separator: ", ")) · \(time)"
        }
    }
}

enum WorkoutReminderTarget: Equatable {
    case routine(UUID)
    case exercise(ExerciseID)

    private static let typeKey = "workoutReminder.targetType"
    private static let idKey = "workoutReminder.targetID"

    var payload: [String: String] {
        switch self {
        case .routine(let id):
            [Self.typeKey: "routine", Self.idKey: id.uuidString]
        case .exercise(let id):
            [Self.typeKey: "exercise", Self.idKey: id.rawValue]
        }
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let type = userInfo[Self.typeKey] as? String,
              let value = userInfo[Self.idKey] as? String else { return nil }
        switch type {
        case "routine":
            guard let id = UUID(uuidString: value) else { return nil }
            self = .routine(id)
        case "exercise":
            self = .exercise(ExerciseID(rawValue: value))
        default:
            return nil
        }
    }
}

struct WorkoutReminderNotificationRequest: Equatable {
    let identifier: String
    let title: String
    let body: String
    let target: WorkoutReminderTarget
    let dateComponents: DateComponents
    let repeats: Bool
}

/// Builds the bounded set of local calendar notifications for the supported v1 recurrences.
enum WorkoutReminderScheduleBuilder {
    static let identifierPrefix = "fixMyPosture.workoutReminder."
    static let everyOtherDayHorizon = 16

    static func requests(
        settings: WorkoutReminderSettings,
        title: String,
        body: String,
        target: WorkoutReminderTarget,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [WorkoutReminderNotificationRequest] {
        guard settings.enabled else { return [] }
        let settings = settings.normalized(calendar: calendar)

        switch settings.recurrence {
        case .daily:
            return [WorkoutReminderNotificationRequest(
                identifier: identifier("daily"),
                title: title,
                body: body,
                target: target,
                dateComponents: clockComponents(settings: settings),
                repeats: true
            )]
        case .weekly:
            return settings.weekdays.sorted().map { weekday in
                var components = clockComponents(settings: settings)
                components.weekday = weekday
                return WorkoutReminderNotificationRequest(
                    identifier: identifier("weekly.\(weekday)"),
                    title: title,
                    body: body,
                    target: target,
                    dateComponents: components,
                    repeats: true
                )
            }
        case .everyOtherDay:
            return everyOtherDayRequests(
                settings: settings,
                title: title,
                body: body,
                target: target,
                now: now,
                calendar: calendar
            )
        }
    }

    private static func everyOtherDayRequests(
        settings: WorkoutReminderSettings,
        title: String,
        body: String,
        target: WorkoutReminderTarget,
        now: Date,
        calendar: Calendar
    ) -> [WorkoutReminderNotificationRequest] {
        let anchor = calendar.startOfDay(for: settings.everyOtherDayStartDate)
        let today = calendar.startOfDay(for: now)
        let elapsedDays = max(0, calendar.dateComponents([.day], from: anchor, to: today).day ?? 0)
        var occurrenceIndex = elapsedDays / 2
        var result: [WorkoutReminderNotificationRequest] = []

        while result.count < everyOtherDayHorizon {
            guard let day = calendar.date(byAdding: .day, value: occurrenceIndex * 2, to: anchor) else { break }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = settings.hour
            components.minute = settings.minute
            guard let occurrence = calendar.date(from: components) else {
                occurrenceIndex += 1
                continue
            }
            if occurrence > now {
                result.append(WorkoutReminderNotificationRequest(
                    identifier: identifier("everyOtherDay.\(calendar.component(.year, from: day))-\(calendar.component(.month, from: day))-\(calendar.component(.day, from: day))"),
                    title: title,
                    body: body,
                    target: target,
                    dateComponents: components,
                    repeats: false
                ))
            }
            occurrenceIndex += 1
        }
        return result
    }

    /// Triggers carry no time zone, so they follow the device's local wall clock.
    private static func clockComponents(settings: WorkoutReminderSettings) -> DateComponents {
        var components = DateComponents()
        components.hour = settings.hour
        components.minute = settings.minute
        return components
    }

    private static func identifier(_ suffix: String) -> String {
        identifierPrefix + suffix
    }
}
