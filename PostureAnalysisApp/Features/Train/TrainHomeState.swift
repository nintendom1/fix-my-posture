import Foundation

struct TrainHomeRoutinePresentation: Equatable {
    let id: UUID
    let name: String
    let exerciseCount: Int
    let setCount: Int
    let estimatedMinutes: Int?
    let chips: [String]
    let canStart: Bool

    var summary: String {
        let exerciseText = exerciseCount == 1 ? "1 exercise" : "\(exerciseCount) exercises"
        let setText = setCount == 1 ? "1 set" : "\(setCount) sets"
        return "\(exerciseText) · \(setText)"
    }

    var summaryWithEstimate: String {
        guard let estimatedMinutes else { return summary }
        return "\(summary) · about \(estimatedMinutes) min"
    }
}

struct TrainExerciseTile: Equatable, Identifiable {
    let id: ExerciseID
    let name: String
    let target: String
    let gradient: ExerciseGradient
    let symbolName: String
}

struct TrainLastWorkoutPresentation: Equatable {
    let dateLabel: String
    let summary: String
}

struct TrainHomeState: Equatable {
    let dateLabel: String
    let heroRoutine: TrainHomeRoutinePresentation?
    let exercises: [TrainExerciseTile]
    let lastWorkout: TrainLastWorkoutPresentation?

    var showsCreateRoutineEmptyState: Bool { heroRoutine == nil }
}

enum TrainHomeIntent: Equatable {
    case appeared
    case startRoutine
    case startExercise(ExerciseID)
    case createRoutine
    case openSettings
    case openLibrary
    case openHistory
}

enum TrainHomeDateFormatter {
    static func label(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    static func weekday(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}
