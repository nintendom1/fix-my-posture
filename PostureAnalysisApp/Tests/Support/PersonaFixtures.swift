import CoreGraphics
import Foundation
@testable import PostureAnalysisApp

/// Shared builders for Extra Personable tests. Packages may add private helpers in their own test files;
/// only the orchestrator edits this file.
enum PersonaFixtures {
    /// Gregorian, America/Los_Angeles, Monday first, en_US_POSIX (same as `FixedClock.calendar`).
    static var calendar: Calendar { FixedClock.calendar }

    /// A local date in `calendar`.
    static func date(day: Int, month: Int = 10, year: Int = 2026, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static let rows = ExerciseID(rawValue: "dumbbell_row")
    static let press = ExerciseID(rawValue: "shoulder_press")
    static let curls = ExerciseID(rawValue: "hammer_curl")

    static func set(_ reps: Int, lb: Double? = nil, kg: Double? = nil, band: String? = nil) -> RecordedSet {
        let weight: WorkoutWeight?
        if let lb { weight = .mass(lb, .pounds) } else if let kg { weight = .mass(kg, .kilograms) } else if let band { weight = .band(band) } else { weight = nil }
        return RecordedSet(reps: reps, side: nil, weight: weight)
    }

    static func entry(
        _ exerciseID: ExerciseID,
        name: String? = nil,
        outcome: WorkoutRecordEntry.Outcome? = .completed,
        sets: [RecordedSet]
    ) -> WorkoutRecordEntry {
        WorkoutRecordEntry(exerciseID: exerciseID, name: name ?? exerciseID.rawValue, outcome: outcome, sets: sets)
    }

    /// A skipped entry, as saved when the user skips an exercise in a routine.
    static func skipped(_ exerciseID: ExerciseID) -> WorkoutRecordEntry {
        WorkoutRecordEntry(exerciseID: exerciseID, name: exerciseID.rawValue, outcome: .skipped, sets: [])
    }

    /// A workout ending at `end`, lasting `minutes`.
    static func record(
        id: UUID = UUID(),
        endingAt end: Date,
        minutes: Int = 20,
        planID: UUID? = nil,
        planName: String? = nil,
        entries: [WorkoutRecordEntry]? = nil
    ) -> WorkoutRecord {
        WorkoutRecord(
            id: id,
            startedAt: end.addingTimeInterval(TimeInterval(-minutes * 60)),
            endedAt: end,
            planID: planID,
            planName: planName,
            entries: entries ?? [entry(press, sets: [set(10, lb: 15)])]
        )
    }

    /// One plain workout at noon on each given day of October 2026.
    static func workouts(onOctoberDays days: [Int], hour: Int = 12) -> [WorkoutRecord] {
        days.map { record(endingAt: date(day: $0, hour: hour)) }
    }

    /// Character reminders on, daily at 09:00.
    static var reminderSettings: WorkoutReminderSettings {
        var settings = WorkoutReminderSettings()
        settings.enabled = true
        settings.style = .character
        settings.recurrence = .daily
        settings.hour = 9
        settings.minute = 0
        return settings
    }

    /// A front-view assessment with one degree measurement per entry.
    static func assessment(
        date: Date,
        isBaseline: Bool = false,
        measurements: [(MeasurementID, Double)] = [(.shoulderLineAngle, 4)]
    ) -> PostureAssessment {
        PostureAssessment(
            date: date,
            imageRelativePath: "fixture.jpg",
            view: .front,
            pose: BodyPose(landmarks: [:], imageWidth: 600, imageHeight: 1200),
            measurements: measurements.map { id, value in
                PostureMeasurement(id: id, name: id.rawValue, value: value, unit: "°", landmarksUsed: [], confidence: 0.95, explanation: "Geometric observation.")
            },
            isBaseline: isBaseline
        )
    }

    static func observation(
        _ family: ObservationFamily,
        _ kind: String,
        subject: String = "-",
        period: String = "-",
        salience: PersonaSalience,
        strength: Int = 3,
        contentKey: String? = nil,
        values: [String: String] = [:],
        suggestion: PersonaSuggestion? = nil
    ) -> PersonaObservation {
        PersonaObservation(
            key: PersonaObservationKey(family: family, kind: kind, subject: subject, period: period),
            salience: salience,
            evidence: PersonaEvidence(strength: strength, lines: ["fixture"]),
            contentKey: contentKey ?? "\(family.rawValue).\(kind)",
            values: values,
            suggestion: suggestion
        )
    }

    /// A small catalog with every tone's art and one untagged title and body per content key, so planner tests do
    /// not depend on authored copy.
    static func catalog(keys: [String] = PersonaFixtures.contentKeys) -> PersonaContentCatalog {
        let art = NotificationScenario.Art(expression: "smile", outfit: "hoodie", crop: .portrait)
        var entries: [String: PersonaContentEntry] = [:]
        for key in keys {
            let family = ObservationFamily(rawValue: String(key.split(separator: ".")[0])) ?? .achievement
            entries[key] = PersonaContentEntry(
                key: key, family: family, defaultTone: .pleased, tokens: [], sample: [:],
                title: [PersonaCopyVariant(text: "Title \(key)")],
                body: [PersonaCopyVariant(text: "Body \(key)")],
                art: [:]
            )
        }
        return PersonaContentCatalog(
            toneArt: Dictionary(uniqueKeysWithValues: PersonaTone.allCases.map { ($0, art) }),
            fragments: PersonaFragments(intro: [PersonaCopyVariant(text: "Intro.")]),
            entries: entries
        )
    }

    /// Every v1 content key.
    static let contentKeys = [
        "achievement.pr.weight", "achievement.pr.reps", "achievement.milestone",
        "pattern.weekday", "pattern.weekday.established", "pattern.weekday.upcoming", "pattern.routineRepeat", "pattern.timeOfDay",
        "lapse.skippedExercise", "lapse.skippedExercise.escalated", "lapse.neglectedRoutine",
        "lapse.decliningWeeks", "lapse.comeback",
        "posture.returned", "posture.improved",
    ]
}
