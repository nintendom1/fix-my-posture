import Foundation

/// One family's detector. Detectors are pure: they read time only from `asOf` and `context`, never `Date()`.
///
/// - `projected == false`: evaluating the triggering event (a just-saved workout or the current moment). Kinds that
///   need a triggering record (PRs, milestones, comeback, skipped exercise, posture return) are allowed.
/// - `projected == true`: evaluating a future (or later-today) slot at `asOf`, reading history as it stands, so
///   future days project as misses. Only history-state kinds (weekday pattern nudges, neglected routine,
///   declining weeks) may be produced.
protocol PersonaDetecting {
    static func observations(
        _ context: PersonaContext,
        asOf: Date,
        projected: Bool,
        policy: PersonaPolicy
    ) -> [PersonaObservation]
}

/// The detector registry. Adding a family (for example `occasion` for holidays) means one new detector type,
/// its content keys in persona-content.json, and one line here.
enum PersonaDetectors {
    static let all: [any PersonaDetecting.Type] = [
        AchievementDetector.self,
        PatternDetector.self,
        LapseDetector.self,
        PostureDetector.self,
    ]

    /// Every detector's observations, in registry order. Does not rank or filter; the planner does.
    static func observations(
        _ context: PersonaContext,
        asOf: Date,
        projected: Bool,
        policy: PersonaPolicy = .standard
    ) -> [PersonaObservation] {
        // Implemented by P1 (may stay this simple).
        all.flatMap { $0.observations(context, asOf: asOf, projected: projected, policy: policy) }
    }
}

/// Shared, deterministic formatting and filtering used by the Foundation-only detectors.
enum PersonaDetectorSupport {
    static func ordered(_ observations: [PersonaObservation]) -> [PersonaObservation] {
        observations.sorted { $0.key.string < $1.key.string }
    }

    static func freshTriggerRecord(
        in context: PersonaContext,
        asOf: Date,
        policy: PersonaPolicy
    ) -> WorkoutRecord? {
        guard let record = context.trigger.savedRecord,
              record.endedAt <= asOf,
              asOf.timeIntervalSince(record.endedAt) <= Double(policy.achievementFreshnessHours) * 60 * 60 else {
            return nil
        }
        return record
    }

    static func records(_ records: [WorkoutRecord], through date: Date) -> [WorkoutRecord] {
        records.filter { $0.endedAt <= date }
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func weekKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = components.yearForWeekOfYear ?? 0
        let week = components.weekOfYear ?? 0
        return "\(year)-W\(String(format: "%02d", week))"
    }

    static func weekdayName(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    static func formattedHour(_ hour: Int, on day: Date, calendar: Calendar) -> String? {
        guard let date = calendar.date(byAdding: .hour, value: hour, to: calendar.startOfDay(for: day)) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "h a"
        return formatter.string(from: date)
    }

    static func fractionalHour(_ date: Date, calendar: Calendar) -> Double {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60 + Double(parts.second ?? 0) / 3600
    }

    static func kilograms(_ weight: WorkoutWeight?) -> Double? {
        guard let weight else { return nil }
        switch weight {
        case .mass(let value, .pounds):
            return value * 0.45359237
        case .mass(let value, .kilograms):
            return value
        case .band:
            return nil
        }
    }

    static func weightLabel(_ weight: WorkoutWeight?) -> String {
        guard let weight else { return "bodyweight" }
        if case .band = weight { return "" }
        return weight.label
    }

    static func exerciseName(_ id: ExerciseID, entry: WorkoutRecordEntry, context: PersonaContext) -> String {
        context.exerciseNames[id] ?? entry.name
    }

    static func routineName(_ id: UUID, record: WorkoutRecord, context: PersonaContext) -> String {
        context.routineNames[id] ?? record.planName ?? ""
    }
}
